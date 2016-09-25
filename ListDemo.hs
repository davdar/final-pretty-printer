{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module ListDemo where

import Control.Monad
import Control.Applicative
import Control.Monad.Reader
import Control.Monad.Writer
import Control.Monad.State
import Control.Monad.RWS
import Data.List
import Data.String (IsString(..))
import Data.Text (Text)
import qualified Data.Text as T

import System.Console.ANSI

import Pretty

-- Constructor names or built-in syntax
data HsAnn = Ctor | Stx
  deriving (Eq, Ord, Show)

env0 :: Monoid fmt => PEnv Int a fmt
env0 = PEnv
  { maxWidth = 80
  , maxRibbon = 60
  , layout = Break
  , failure = CantFail
  , nesting = 0
  , formatting = mempty
  , formatAnn = const mempty
  }

state0 :: PState Int ()
state0 = PState
  { curLine = []
  }

-- For plain text pretty printing
newtype DocM a = DocM { unDocM :: RWST (PEnv Int HsAnn ()) (POut Int HsAnn) (PState Int ()) Maybe a }
  deriving
    ( Functor, Applicative, Monad
    , MonadReader (PEnv Int HsAnn ()), MonadWriter (POut Int HsAnn), MonadState (PState Int ()), Alternative
    )

instance MonadPretty Int HsAnn () DocM

instance IsString (DocM ()) where
  fromString = text . fromString

runDocM :: PEnv Int HsAnn () -> PState Int () -> DocM a -> Maybe (PState Int (), POut Int HsAnn, a)
runDocM e s d = (\(a,s',o) -> (s',o,a)) <$> runRWST (unDocM d) e s

execDoc :: Doc -> POut Int HsAnn
execDoc d =
  let rM = runDocM env0 state0 d
  in case rM of
    Nothing -> PAtom $ AChunk $ CText "<internal pretty printing error>"
    Just (_, o, ()) -> o

type Doc = DocM ()

instance Monoid Doc where
  mempty = return ()
  mappend = (>>)

class Pretty a where
  pretty :: a -> Doc
instance Pretty Doc where
  pretty = id

instance Measure Int () DocM where
  measure = return . runIdentity . measure

instance Pretty Text where
  pretty = annotate Ctor . text . T.pack . show

instance (Pretty a) => Pretty [a] where
  pretty = collection (annotate Stx "[") (annotate Stx "]") (annotate Stx ",") . map pretty

renderChunk :: Chunk Int -> String
renderChunk (CText t) = T.unpack t
renderChunk (CSpace w) = replicate w ' '

renderAtom :: Atom Int -> String
renderAtom (AChunk c) = renderChunk c
renderAtom ANewline = "\n"

render :: forall m ann .
          Monad m
       => (ann -> m ()) -> (ann -> m ())
       -> (String -> m ())
       -> POut Int ann -> m ()
render start end str out = render' out
  where
    render' :: POut Int ann -> m ()
    render' PNull = str ""
    render' (PAtom a) = str $ renderAtom a
    render' (PSeq o1 o2) = do
      render' o1
      render' o2
    render' (PAnn a o) = start a >> render' o >> end a


instance Show Doc where
  show = snd . runWriter . render (const (pure ())) (const (pure ())) tell . execDoc

toHtml :: Doc -> String
toHtml = snd . runWriter . render openTag closeTag tell . execDoc
  where openTag Ctor = tell "<span class=\"constructor\">"
        openTag Stx  = tell "<span class=\"syntax\">"
        closeTag _   = tell "</span>"

dumpDoc :: Doc -> IO ()
dumpDoc = flip evalStateT [] . render openTag closeTag out . execDoc
  where out :: String -> StateT [HsAnn] IO ()
        out = lift . putStr
        toSGR :: HsAnn -> [SGR]
        toSGR Ctor = [SetConsoleIntensity BoldIntensity, SetColor Foreground Vivid Red]
        toSGR Stx  = [SetConsoleIntensity BoldIntensity, SetColor Foreground Vivid Black]
        updateColor :: StateT [HsAnn] IO ()
        updateColor =
          lift . setSGR =<< mconcat . map toSGR . reverse <$> get
        openTag :: HsAnn -> StateT [HsAnn] IO ()
        openTag ann = modify (ann:) >> updateColor
        closeTag :: HsAnn -> StateT [HsAnn] IO ()
        closeTag _  = modify tail   >> updateColor

---------------
-- Test docs --
---------------

shortList :: [[Text]]
shortList = [["a", "b", "c"], [], ["longer"]]

longList :: [[Text]]
longList = [map (T.pack . show) [1..10], [], map (T.pack . flip replicate 'a') [1..10]]

-- To try, eval dumpDoc (pretty shortList) or dumpDoc (pretty longList) in console GHCI
