module Main where

import           Control.Monad (unless)
import qualified Data.ByteString.Lazy as LBS
import           Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import           Network.HTTP.Client (Manager, defaultManagerSettings, newManager)
import           Network.HTTP.Conduit (httpLbs, parseRequest, responseBody)
import           Options.Applicative
                  (Parser, execParser, fullDesc, header, help, helper, info, long, metavar, option,
                  short, showDefault, str, switch, value)
import qualified System.Directory as Dir
import           System.FilePath ((</>))
import qualified System.FilePath as F
import           System.Info (os)
import           System.Process (callProcess)

data MavenPackage = MavenPackage
  { _mpGroupId    :: Text
  , _mpArtifactId :: Text
  , _mpVersion    :: Text
  } deriving (Show, Eq)

-- | Download the jar file for this Maven package.
fetchMavenPackage :: Manager
                  -> FilePath      -- ^ Folder to download the file into
                  -> MavenPackage  -- ^ The Maven package to download
                  -> IO ()
fetchMavenPackage manager folder MavenPackage{..} = do
  Dir.createDirectoryIfMissing True folder
  let packageFilePath = folder </> T.unpack mavenFileName
  packageExists <- Dir.doesFileExist packageFilePath
  unless packageExists $ do
    putStrLn $ T.unpack mavenUrl <> " --> " <> packageFilePath
    request <- parseRequest $ T.unpack mavenUrl
    httpLbs request manager >>= LBS.writeFile packageFilePath . responseBody
  where
    -- | Gets the name of the jar file of this Maven package.
    mavenFileName :: Text
    mavenFileName = _mpArtifactId <> "-" <> _mpVersion <> ".jar"

    mavenUrl :: Text
    mavenUrl =
      let urlParts = T.splitOn "." _mpGroupId ++ [_mpArtifactId, _mpVersion, mavenFileName]
      in "http://search.maven.org/remotecontent?filepath=" <> T.intercalate "/" urlParts

-- | Downloads all the required jars from Maven and returns a classpath string
--   that includes all those jars.
fetchMavenPackages :: Manager
                   -> FilePath      -- ^ Folder into which to save the jars.
                   -> IO [FilePath] -- ^ The absolute `FilePath` to each jar.
fetchMavenPackages manager jarFolder = do
  absoluteJarFolder <- Dir.makeAbsolute jarFolder
  putStrLn "Fetching required jars..."
  fetchMavenPackage manager absoluteJarFolder `mapM_` mavenPackages
  putStrLn "Done."
  getJarFilePaths absoluteJarFolder
  where
    getJarFilePaths path =
      fmap (F.combine path) . filter (F.isExtensionOf ".jar") <$> Dir.listDirectory path

mavenPackages :: [MavenPackage]
mavenPackages =
  [ MavenPackage "com.amazonaws" "amazon-kinesis-client" "1.9.0"
  , MavenPackage "com.amazonaws" "aws-java-sdk-dynamodb" "1.11.273"
  , MavenPackage "com.amazonaws" "aws-java-sdk-s3" "1.11.273"
  , MavenPackage "com.amazonaws" "aws-java-sdk-kms" "1.11.273"
  , MavenPackage "com.amazonaws" "aws-java-sdk-core" "1.11.273"
  , MavenPackage "org.apache.httpcomponents" "httpclient" "4.5.2"
  , MavenPackage "org.apache.httpcomponents" "httpcore" "4.4.4"
  , MavenPackage "commons-codec" "commons-codec" "1.9"
  , MavenPackage "com.fasterxml.jackson.core" "jackson-databind" "2.6.6"
  , MavenPackage "com.fasterxml.jackson.core" "jackson-annotations" "2.6.0"
  , MavenPackage "com.fasterxml.jackson.core" "jackson-core" "2.6.6"
  , MavenPackage "com.fasterxml.jackson.dataformat" "jackson-dataformat-cbor" "2.6.6"
  , MavenPackage "joda-time" "joda-time" "2.8.1"
  , MavenPackage "com.amazonaws" "aws-java-sdk-kinesis" "1.11.273"
  , MavenPackage "com.amazonaws" "aws-java-sdk-cloudwatch" "1.11.273"
  , MavenPackage "com.google.guava" "guava" "18.0"
  , MavenPackage "com.google.protobuf" "protobuf-java" "2.6.1"
  , MavenPackage "commons-lang" "commons-lang" "2.6"
  , MavenPackage "commons-logging" "commons-logging" "1.1.3" ]

data Options = Options
  { _oJavaLocation       :: FilePath
  , _oPropertiesFilePath :: FilePath
  , _oJarFolder          :: FilePath
  , _oShouldExecute      :: Bool
  } deriving (Show, Eq)

loadOptions :: IO Options
loadOptions = execParser $
  info (helper <*> optionsParser) (fullDesc <> header "BootStrap")

optionsParser :: Parser Options
optionsParser =
  Options
    <$> javaLocationOpt
    <*> propertiesOpt
    <*> jarFolderOpt
    <*> shouldExecuteFlag
  where
    javaLocationOpt = option str $
      long "java"
      <> short 'j'
      <> metavar "PATH"
      <> help "Path to java, used to start the KCL multi-lang daemon."
      <> value "java"
      <> showDefault
    propertiesOpt = option str $
      long "properties"
      <> short 'p'
      <> metavar "PATH"
      <> help "Path to properties file used to configure the KCL."
      <> showDefault
    jarFolderOpt = option str $
      long "jar-folder"
      <> metavar "PATH"
      <> help "Folder to place required jars in."
      <> value "./jars"
      <> showDefault
    shouldExecuteFlag = switch $
      long "execute"
      <> short 'e'
      <> help "Actually launch the KCL. If not specified, \
              \prints the command used to launch the KCL."

validateJavaLocation :: FilePath -> IO ()
validateJavaLocation javaLocation = callProcess javaLocation ["-version"]
  -- TODO better exception

printMultiLangDaemonCommand :: [FilePath] -> IO ()
printMultiLangDaemonCommand = T.putStrLn . forkOp . T.intercalate " " . fmap (escape . T.pack)
  where
    escape t = "\"" <> t <> "\""
    forkOp = if os == "mingw32" then ("& " <>) else id

joinClassPaths :: FilePath -> [FilePath] -> String
joinClassPaths jarPath jarPaths =
  T.unpack $ T.intercalate seperator $ T.pack <$> allPaths
  where seperator = T.singleton F.searchPathSeparator
        allPaths = jarPath : jarPaths

main :: IO ()
main = do
  Options{..} <- loadOptions
  validateJavaLocation _oJavaLocation
  manager <- newManager defaultManagerSettings
  absoluteJarFolder <- Dir.makeAbsolute _oJarFolder
  absoluteJarPaths <- fetchMavenPackages manager absoluteJarFolder
  let arguments =
        [ "-cp"
        , joinClassPaths absoluteJarFolder absoluteJarPaths
        , "com.amazonaws.services.kinesis.multilang.MultiLangDaemon"
        , _oPropertiesFilePath ]
  if _oShouldExecute
    then do
      putStrLn "Starting MultiLangDaemon"
      callProcess _oJavaLocation arguments
    else printMultiLangDaemonCommand $ _oJavaLocation : arguments
