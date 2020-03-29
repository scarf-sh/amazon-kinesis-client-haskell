module Main where

import           Control.Exception.Safe (handleAny)
import qualified Data.Text as T
import           Network.AWS.Kinesis.Client

main :: IO ()
main =
  handleAny (kclPutStrLn . T.pack . show) $
    runKCL initialise processRecords shutdown
  where
    initialise InitialisationInput{..} =
      kclPutStrLn $ T.pack $ "Initializing record processor for shard: " <> show _iiShardId
    processRecords ProcessRecordsInput{..} =
      kclPutStrLn $ T.pack $
        "Processing " <> show (length _priRecords) <> " records from " <> show _priShardId
      -- Your own logic to process a record goes here.
    shutdown ShutdownInput{..} =
      kclPutStrLn $ T.pack $ "Shutting down record processor for shard: " <> show _siShardId
