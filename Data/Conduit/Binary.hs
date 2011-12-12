{-# LANGUAGE FlexibleContexts #-}
module Data.Conduit.Binary
    ( sourceFile
    , sinkFile
    , isolate
    ) where

import Prelude hiding (FilePath)
import System.IO (hClose)
import Filesystem.Path.CurrentOS (FilePath)
import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import Filesystem (openFile, IOMode (ReadMode, WriteMode))
import Data.Conduit
import Control.Monad.Trans.Resource (with, release)
import Data.Int (Int64)

sourceFile :: MonadBaseControl IO m
           => FilePath
           -> SourceM m S.ByteString
sourceFile fp = sourceM
    (with (liftBase $ openFile fp ReadMode) (liftBase . hClose))
    (\(key, _) -> release key)
    (\(_, handle) -> do
        bs <- liftBase $ S.hGetSome handle 4096
        if S.null bs
            then return EOF
            else return $ Chunks [bs])

sinkFile :: MonadBaseControl IO m
         => FilePath
         -> SinkM S.ByteString m ()
sinkFile fp = sinkM
    (with (liftBase $ openFile fp WriteMode) (liftBase . hClose))
    (\(key, _) -> release key)
    (\(_, handle) bss -> liftBase (L.hPut handle $ L.fromChunks bss) >> return (SinkResult [] Nothing))
    (const $ return $ SinkResult [] ())

isolate :: MonadBaseControl IO m
        => Int64
        -> ConduitM S.ByteString m S.ByteString
isolate count0 = conduitMState
    count0
    push
    (const $ return [])
  where
    push 0 bss = return (0, ConduitResult bss EOF)
    push count bss = do
        let (a, b) = L.splitAt count $ L.fromChunks bss
        let count' = count - L.length a
        return (count', ConduitResult (L.toChunks b) (Chunks $ L.toChunks a))
