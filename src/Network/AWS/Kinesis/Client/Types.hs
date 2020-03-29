{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralisedNewtypeDeriving #-}

module Network.AWS.Kinesis.Client.Types
  ( ShardId(..)
  , SequenceNumber(..)
  , ReceiveAction(..)
  , SendAction(..)
  , KCLStatus(..)
  , ShutdownReason(..)
  , Record
  , record
  , rEncryptionType
  , rApproximateArrivalTimestamp
  , rSequenceNumber
  , rData
  , rPartitionKey
  , EncryptionType(..)
  , KCLState(..)
  , CheckPointer
  , InitialisationInput(..)
  , ProcessRecordsInput(..)
  , ShutdownInput(..)
  , KCLException(..)
  ) where

import           Control.Exception (Exception)
import           Control.Lens (Iso', Lens', iso, lens, mapping, ( # ))
import           Data.Aeson
                  (FromJSON(..), ToJSON(..), Value(..), object, withObject, withText, (.:), (.:?),
                  (.=))
import qualified Data.ByteArray.Encoding as BA
import           Data.ByteString (ByteString)
import           Data.Semigroup ((<>))
import           Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as T
import           Data.Time (UTCTime)
import           Data.Time.Clock.POSIX (POSIXTime, posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import           Data.Typeable (Typeable)
import           GHC.Generics (Generic)

newtype ShardId = ShardId Text
  deriving (Eq, Generic, FromJSON)

instance Show ShardId where
  show (ShardId shardId) = T.unpack shardId

newtype SequenceNumber = SequenceNumber Text
  deriving (Eq, Generic, ToJSON, FromJSON)

instance Show SequenceNumber where
  show (SequenceNumber sequenceNumber) = T.unpack sequenceNumber

data ReceiveAction
  = ReceiveInitialise     !ShardId
  | ReceiveProcessRecords ![Record]
  | ReceiveShutdown       !ShutdownReason
  | ReceiveCheckpoint     !SequenceNumber !(Maybe String)
  deriving (Eq, Generic)

instance FromJSON ReceiveAction where
  parseJSON = withObject "Action" $ \o ->
    o .: "action" >>= \case
      Initialise     -> ReceiveInitialise <$> o .: "shardId"
      ProcessRecords -> ReceiveProcessRecords <$> o .: "records"
      Shutdown       -> ReceiveShutdown <$> o .: "reason"
      Checkpoint     -> ReceiveCheckpoint <$> o .: "sequenceNumber" <*> o .:? "error"

data SendAction
  = SendCheckpoint !SequenceNumber
  | SendStatus     !KCLStatus
  deriving (Eq, Show, Generic)

instance ToJSON SendAction where
  toJSON = \case
    SendCheckpoint sequenceNumber ->
      object [ "action" .= String "checkpoint", "sequenceNumber" .= sequenceNumber ]
    SendStatus status ->
      object [ "action" .= String "status", "responseFor" .= status ]

data KCLStatus
  = Initialise
  | ProcessRecords
  | Shutdown
  | Checkpoint
  deriving (Eq, Ord, Generic, Enum, Bounded)

instance Show KCLStatus where
  show = \case
    Initialise     -> "initialize"
    ProcessRecords -> "processRecords"
    Shutdown       -> "shutdown"
    Checkpoint     -> "checkpoint"

instance ToJSON KCLStatus where
  toJSON = String . T.pack . show

instance FromJSON KCLStatus where
  parseJSON = withText "KCLStatus" $ \t -> case T.toLower t of
    "initialize"     -> pure Initialise
    "processrecords" -> pure ProcessRecords
    "shutdown"       -> pure Shutdown
    "checkpoint"     -> pure Checkpoint
    _                -> fail $ "Unknown value for status: " <> T.unpack t

data ShutdownReason
  = Zombie -- ^ Processing will be moved to a different record processor (fail over, load balancing use cases). Applications SHOULD NOT checkpoint their progress (as another record processor may have already started processing data).
  | Terminate -- ^ Terminate processing for this RecordProcessor (resharding use case). Indicates that the shard is closed and all records from the shard have been delivered to the application. Applications SHOULD checkpoint their progress to indicate that they have successfully processed all records from this shard and processing of child shards can be started.
  deriving (Eq, Ord, Read, Show, Generic, Enum, Bounded)

instance FromJSON ShutdownReason where
  parseJSON = withText "ShutdownReason" $ \t -> case T.toLower t of
    "zombie"    -> pure Zombie
    "terminate" -> pure Terminate
    _           -> fail $ "Unknown value for shutdown reason: " <> T.unpack t

newtype Base64 = Base64 { unBase64 :: ByteString }
  deriving (Eq, Read, Ord, Generic)

instance FromJSON Base64 where
  parseJSON = withText "Base64" $
    either fail (pure . Base64) . BA.convertFromBase BA.Base64 . T.encodeUtf8

_Base64 :: Iso' Base64 ByteString
_Base64 = iso unBase64 Base64

_Time :: Iso' POSIXTime UTCTime
_Time = iso posixSecondsToUTCTime utcTimeToPOSIXSeconds

data EncryptionType
  = KMS
  | None
  deriving (Eq, Ord, Read, Show, Generic, Enum, Bounded)

instance FromJSON EncryptionType where
  parseJSON = withText "EncryptionType" $ \t -> case T.toLower t of
    "kms"  -> pure KMS
    "none" -> pure None
    _      -> fail $ "Unknown value for encryption type: " <> T.unpack t

-- | The unit of data of the Kinesis data stream, which is composed of a sequence number, a partition key, and a data blob.
--
--
--
-- /See:/ 'record' smart constructor.
data Record = Record
  { _rEncryptionType              :: !(Maybe EncryptionType)
  , _rApproximateArrivalTimestamp :: !(Maybe POSIXTime)
  , _rSequenceNumber              :: !SequenceNumber
  , _rData                        :: !Base64
  , _rPartitionKey                :: !Text
  } deriving (Eq)


-- | Creates a value of 'Record' with the minimum fields required to make a request.
--
-- Use one of the following lenses to modify other fields as desired:
--
-- * 'rEncryptionType' - The encryption type used on the record. This parameter can be one of the following values:     * @NONE@ : Do not encrypt the records in the stream.     * @KMS@ : Use server-side encryption on the records in the stream using a customer-managed AWS KMS key.
--
-- * 'rApproximateArrivalTimestamp' - The approximate time that the record was inserted into the stream.
--
-- * 'rSequenceNumber' - The unique identifier of the record within its shard.
--
-- * 'rData' - The data blob. The data in the blob is both opaque and immutable to Kinesis Data Streams, which does not inspect, interpret, or change the data in the blob in any way. When the data blob (the payload before base64-encoding) is added to the partition key size, the total size must not exceed the maximum record size (1 MB).-- /Note:/ This 'Lens' automatically encodes and decodes Base64 data. The underlying isomorphism will encode to Base64 representation during serialisation, and decode from Base64 representation during deserialisation. This 'Lens' accepts and returns only raw unencoded data.
--
-- * 'rPartitionKey' - Identifies which shard in the stream the data record is assigned to.
record
    :: SequenceNumber -- ^ 'rSequenceNumber'
    -> ByteString -- ^ 'rData'
    -> Text -- ^ 'rPartitionKey'
    -> Record
record sequenceNumber data' partitionKey =
  Record
    { _rEncryptionType = Nothing
    , _rApproximateArrivalTimestamp = Nothing
    , _rSequenceNumber = sequenceNumber
    , _rData = _Base64 # data'
    , _rPartitionKey = partitionKey
    }

-- | The encryption type used on the record. This parameter can be one of the following values:     * @NONE@ : Do not encrypt the records in the stream.     * @KMS@ : Use server-side encryption on the records in the stream using a customer-managed AWS KMS key.
rEncryptionType :: Lens' Record (Maybe EncryptionType)
rEncryptionType = lens _rEncryptionType (\ s a -> s{_rEncryptionType = a})

-- | The approximate time that the record was inserted into the stream.
rApproximateArrivalTimestamp :: Lens' Record (Maybe UTCTime)
rApproximateArrivalTimestamp =
  lens _rApproximateArrivalTimestamp (\ s a -> s{_rApproximateArrivalTimestamp = a}) . mapping _Time

-- | The unique identifier of the record within its shard.
rSequenceNumber :: Lens' Record SequenceNumber
rSequenceNumber = lens _rSequenceNumber (\ s a -> s{_rSequenceNumber = a})

-- | The data blob. The data in the blob is both opaque and immutable to Kinesis Data Streams, which does not inspect, interpret, or change the data in the blob in any way. When the data blob (the payload before base64-encoding) is added to the partition key size, the total size must not exceed the maximum record size (1 MB).-- /Note:/ This 'Lens' automatically encodes and decodes Base64 data. The underlying isomorphism will encode to Base64 representation during serialisation, and decode from Base64 representation during deserialisation. This 'Lens' accepts and returns only raw unencoded data.
rData :: Lens' Record ByteString
rData = lens _rData (\ s a -> s{_rData = a}) . _Base64

-- | Identifies which shard in the stream the data record is assigned to.
rPartitionKey :: Lens' Record Text
rPartitionKey = lens _rPartitionKey (\ s a -> s{_rPartitionKey = a})

instance FromJSON Record where
  parseJSON = withObject "Record" $ \o ->
    Record
    <$> o .:? "encryptionType"
    <*> o .:? "approximateArrivalTimestamp"
    <*> o .: "sequenceNumber"
    <*> o .: "data"
    <*> o .: "partitionKey"

data KCLState
  = KCLInit
  | KCLReady
  | KCLFinished
  deriving (Eq, Ord, Read, Show, Generic, Enum, Bounded)

type CheckPointer m = SequenceNumber -> m ()

newtype InitialisationInput = InitialisationInput
  { _iiShardId :: ShardId
  }

data ProcessRecordsInput m = ProcessRecordsInput
  { _priShardId      :: ShardId
  , _priRecords      :: [Record]
  , _priCheckpointer :: CheckPointer m
  }

data ShutdownInput m = ShutdownInput
  { _siShardId        :: ShardId
  , _siShutdownReason :: ShutdownReason
  , _siCheckpointer   :: CheckPointer m
  }

data KCLException
  = KCLUnexpectedState KCLStatus (Maybe KCLStatus)
  | KCLCheckpointError String
  | KCLActionParseError String
  | KCLCannotReadAction
  deriving (Eq, Typeable, Generic)

instance Exception KCLException

instance Show KCLException where
  show = \case
    KCLUnexpectedState received Nothing ->
      "Unexpected state '" <> show received
    KCLUnexpectedState received (Just expected) ->
      "Unexpected state '" <> show received <> "' instead of '" <> show expected <> "'"
    KCLCheckpointError e ->
      "An error occured when trying to checkpoint: " <> e
    KCLActionParseError e ->
      "Unable to parse action from the KCL deamon: " <> e
    KCLCannotReadAction ->
      "Unable to read an action from the KCL deamon"
