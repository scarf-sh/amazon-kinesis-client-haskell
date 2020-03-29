module Network.AWS.Kinesis.Client
  ( module Network.AWS.Kinesis.Client.Types
  , runKCL
  , KCLDaemon(..)
  , kclWriteStatus
  ) where

import           Control.Monad.Catch (MonadThrow(..))
import           Data.Aeson (eitherDecode', encode)
import           Data.Text (Text)
import qualified Data.Text.IO as T
import qualified Data.Text.Lazy.Encoding as LT
import qualified Data.Text.Lazy.IO as LT
import           System.IO (BufferMode(LineBuffering))
import qualified System.IO as IO

import           Network.AWS.Kinesis.Client.Types

class (Monad m) => KCLDaemon m where
  kclInit        :: m ()
  kclReadAction  :: m ReceiveAction
  kclWriteAction :: SendAction -> m ()
  kclPutStrLn    :: Text -> m ()

kclWriteStatus :: (KCLDaemon m) => KCLStatus -> m ()
kclWriteStatus = kclWriteAction . SendStatus

instance KCLDaemon IO where
  kclInit = IO.hSetBuffering IO.stdout LineBuffering
  kclReadAction = IO.isEOF >>= \case
    True  -> throwM KCLCannotReadAction
    False -> (eitherDecode' . LT.encodeUtf8 <$> LT.getLine) >>= \case
      Left e -> throwM $ KCLActionParseError e
      Right action -> pure action
  kclWriteAction = LT.putStrLn . LT.decodeUtf8 . encode
  kclPutStrLn = T.hPutStrLn IO.stderr

runKCL :: forall m.
  ( MonadThrow m
  , KCLDaemon m)
  => (InitialisationInput -> m ())
  -> (ProcessRecordsInput m -> m ())
  -> (ShutdownInput m -> m ())
  -> m ()
runKCL kclInitialise kclProcessRecords kclShutdown = initKCL
  where
    initKCL :: m ()
    initKCL = kclInit >> kclReadAction >>= \case
      ReceiveInitialise shardId -> initialise shardId >> runKCL' shardId
      ReceiveProcessRecords{}   -> throwM $ KCLUnexpectedState ProcessRecords $ Just Initialise
      ReceiveShutdown{}         -> throwM $ KCLUnexpectedState Shutdown       $ Just Initialise
      ReceiveCheckpoint{}       -> throwM $ KCLUnexpectedState Checkpoint     $ Just Initialise

    runKCL' :: ShardId -> m ()
    runKCL' shardId = kclReadAction >>= \case
      ReceiveProcessRecords records -> processRecords shardId records  >> runKCL' shardId
      ReceiveShutdown       reason  -> shutdown       shardId reason   >> pure ()
      ReceiveInitialise{}           -> throwM $ KCLUnexpectedState Initialise Nothing
      ReceiveCheckpoint{}           -> throwM $ KCLUnexpectedState Checkpoint Nothing

    initialise :: ShardId -> m ()
    initialise shardId = do
      kclInitialise $ InitialisationInput shardId
      kclWriteStatus Initialise

    processRecords :: ShardId -> [Record] -> m ()
    processRecords shardId records = do
      kclProcessRecords $ ProcessRecordsInput shardId records checkpointer
      kclWriteStatus ProcessRecords

    shutdown :: ShardId -> ShutdownReason -> m ()
    shutdown shardId shutdownReason = do
      kclShutdown $ ShutdownInput shardId shutdownReason checkpointer
      kclWriteStatus Shutdown

    checkpointer :: CheckPointer m
    checkpointer sequenceNumber = do
      kclWriteAction $ SendCheckpoint sequenceNumber
      kclReadAction >>= \case
        ReceiveCheckpoint _ (Just e) -> throwM $ KCLCheckpointError e
        ReceiveCheckpoint{}          -> pure ()
        ReceiveInitialise{}          -> throwM $ KCLUnexpectedState Initialise     $ Just Checkpoint
        ReceiveProcessRecords{}      -> throwM $ KCLUnexpectedState ProcessRecords $ Just Checkpoint
        ReceiveShutdown{}            -> throwM $ KCLUnexpectedState Shutdown       $ Just Checkpoint
