module BitMEXClient.Wrapper.API
    ( makeRequest
    , connect
    , withConnectAndSubscribe
    , makeTimestamp
    , getMessage
    , sendMessage
    , dispatchRequest
    , retryOn503
    ) where

import           BitMEX
    ( AuthApiKeyApiKey (..)
    , AuthBitMEXApiMAC (..)
    , BitMEXConfig (..)
    , BitMEXRequest (..)
    , MimeError (..)
    , MimeFormUrlEncoded
    , MimeResult
    , MimeResult (..)
    , MimeType
    , MimeUnrender
    , ParamBody (..)
    , Produces
    , addAuthMethod
    , dispatchMime
    , paramsBodyL
    , paramsQueryL
    , setHeader
    )
import           Control.Concurrent            (threadDelay)
import           Control.Monad
import           Data.Either                   (Either (..))
import qualified Network.HTTP.Client           as NH
    ( Response (..)
    )
import qualified Network.HTTP.Types            as NH
    ( Status (..)
    )

-- FIX ME!!! Too many little things to import here. Having to import GHC.Num to have (+) work broke the camels back.
-- We should ditch CustomPrelude until it is polished enough.
import           Prelude

import           BitMEX.Logging
import           BitMEXClient.CustomPrelude
import           BitMEXClient.WebSockets.Types
    ( Command (..)
    , Message (..)
    , Response (..)
    , Symbol
    , Topic (..)
    )
import           BitMEXClient.Wrapper.Logging
import           BitMEXClient.Wrapper.Types
import           BitMEXClient.Wrapper.Util
import qualified Data.ByteString.Char8         as BC
    ( pack
    , unpack
    )
import           Data.ByteString.Conversion
    ( toByteString'
    )
import qualified Data.ByteString.Lazy          as LBS
    ( ByteString
    , append
    )
import qualified Data.ByteString.Lazy.Char8    as LBC
    ( pack
    , unpack
    )
import qualified Data.Text                     as T (pack)
import qualified Data.Text.Lazy                as LT
    ( pack
    , toStrict
    )
import qualified Data.Text.Lazy.Encoding       as LT
    ( decodeUtf8
    )
import           Data.Vector                   (fromList)

import           Data.Aeson
    ( eitherDecode
    )

------------------------------------------------------------
-- REST

makeRESTConfig ::
       ( HasReader "environment" Environment m
       , HasReader "logContext" LogContext m
       , HasReader "pathREST" (Maybe LBS.ByteString) m
       )
    => m BitMEXConfig
makeRESTConfig = do
    env <- ask @"environment"
    logCxt <- ask @"logContext"
    path <-
        ask @"pathREST" >>= \p ->
            return $
            case p of
                Nothing -> "/api/v1"
                Just x  -> x
    let base = (LBC.pack . show) env
    return
        BitMEXConfig
        { configHost = LBS.append base path
        , configUserAgent =
              "swagger-haskell-http-client/1.0.0"
        , configLogExecWithContext = runDefaultLogExecWithContext
        , configLogContext = logCxt
        , configAuthMethods = []
        , configValidateAuthMethods = True
        }

-- | Prepare, authenticate and dispatch a request
-- via the auto-generated BitMEX REST API.
makeRequest ::
      ( Produces req accept
      , MimeUnrender accept res
      , MimeType contentType
      , Authenticator m
      , HasReader "environment" Environment m
      , HasReader "logContext" LogContext m
      , HasReader "manager" (Maybe Manager) m
      , HasReader "pathREST" (Maybe LBS.ByteString) m
      , MonadIO m
      )
   => BitMEXRequest req contentType res accept
   -> m (MimeResult res)
makeRequest req@BitMEXRequest {..} = do
    logCxt <- ask @"logContext"
    time <- liftIO $ makeTimestamp <$> getPOSIXTime
    config0 <-
        makeRESTConfig >>=
        liftIO . return . withLoggingBitMEXConfig logCxt
    let verb = filter (/= '"') $ show rMethod
        query = rParams ^. paramsQueryL
        msg = case rParams ^. paramsBodyL of
            ParamBodyBL lbs ->
                    (BC.pack
                         (verb <> "/api/v1" <>
                          (LBC.unpack . head) rUrlPath <>
                          BC.unpack (renderQuery True query) <>
                          show time <>
                          LBC.unpack lbs))
            ParamBodyB bs ->
                    (BC.pack
                         (verb <> "/api/v1" <>
                          (LBC.unpack . head) rUrlPath <>
                          BC.unpack (renderQuery True query) <>
                          show time <>
                          BC.unpack bs))
            _ ->
                    (BC.pack
                         (verb <> "/api/v1" <>
                          (LBC.unpack . head) rUrlPath <>
                          BC.unpack (renderQuery True query) <>
                          show time))
    let new =
            setHeader
                req
                [("api-expires", toByteString' time)]
    config <- authRESTConfig config0 msg
    mgr <-
        ask @"manager" >>= \m ->
            case m of
                Nothing ->
                    liftIO $ newManager tlsManagerSettings
                Just x -> return x
    liftIO $ dispatchMime mgr config new

------------------------------------------------------------
-- WebSocket

-- | Establish connection to the BitMEX WebSocket API,
-- authenticate the user and subscribe to the provided topics.
withConnectAndSubscribe ::
       BitMEXWrapperConfig
    -> [Topic Symbol]
    -> ClientApp a
    -> IO a
withConnectAndSubscribe config@BitMEXWrapperConfig {..} ts app = do
    time <- makeTimestamp <$> getPOSIXTime
    let base = (drop 8 . show) environment
        path =
            case pathWS of
                Nothing -> "/realtime"
                Just x  -> x
    withSocketsDo $
        runSecureClient base 443 (LBC.unpack path) $ \c -> do
            run (authWSMessage time) config >>= sendMessage c AuthKey
            sendMessage c Subscribe ts
            app c

-- | Establish connection to the BitMEX WebSocket API.
connect :: BitMEXWrapperConfig -> BitMEXApp () -> IO ()
connect initConfig@BitMEXWrapperConfig {..} app = do
    let base = (drop 8 . show) environment
        path =
            case pathWS of
                Nothing -> "/realtime"
                Just x  -> x
    config <-
        return $
        withLoggingBitMEXWrapper logContext initConfig
    withSocketsDo $
        runSecureClient base 443 (LBC.unpack path) $ \conn -> do
            run (app conn) config

-- | Receive a message from the WebSocket connection and parse it.
getMessage ::
       Connection
    -> BitMEXWrapperConfig
    -> IO (Maybe Response)
getMessage conn config = do
    msg <- receiveData conn
    runConfigLogWithExceptions "WebSocket" config $ do
        case (eitherDecode msg :: Either String Response) of
            Left e -> do
                errorLog $ LBC.pack e <> ": " <> msg
                return Nothing
            Right r -> do
                case r of
                    P _ -> do
                        log' "Positions" msg
                        return (Just r)
                    OB10 _ -> do
                        log' "OB10" msg
                        return (Just r)
                    Exe _ -> do
                        log' "Execution" msg
                        return (Just r)
                    O _ -> do
                        log' "Order" msg
                        return (Just r)
                    M _ -> do
                        log' "Margin" msg
                        return (Just r)
                    Error _ -> do
                        errorLog msg
                        return (Just r)
                    _ -> do
                        log' "WebSocket" msg
                        return (Just r)
  where
    log' s msg =
        _log s levelInfo $ (LT.toStrict . LT.decodeUtf8) msg
    errorLog msg =
        _log "WebSocket Error" levelError $
        (LT.toStrict . LT.decodeUtf8) msg

-- | Send a message to the WebSocket connection.
sendMessage ::
       (ToJSON a) => Connection -> Command -> [a] -> IO ()
sendMessage conn comm topics =
    sendTextData conn $
    encode $ Message {op = comm, args = fromList topics}

----------------------------------------
makeBitMEXRESTConfig :: BitMEX -> BitMEXConfig
makeBitMEXRESTConfig BitMEX{..} =
    let baseURL = LBC.pack $ show netEnv <> restPath
     in BitMEXConfig
        { configHost                = baseURL -- This is misnamed, it's not just the hostname
        , configUserAgent           = "haskell"
        , configLogExecWithContext  = runDefaultLogExecWithContext
        , configLogContext          = logConfig
        , configAuthMethods         = []
        , configValidateAuthMethods = True
        }

generateAuthInfo :: BitMEX -> BitMEXConfig -> BitMEXConfig
generateAuthInfo BitMEX{..} config =
    config
        `addAuthMethod` AuthApiKeyApiKey ( T.pack $ apiId     apiCreds)
        `addAuthMethod` AuthBitMEXApiMAC (BC.pack $ apiSecret apiCreds)
        -- `addAuthMethod` AuthApiKeyApiSignature (T.pack $ show $ sign (BC.pack $ apiSecret apiCreds) msg)
        -- (This old method would force me to generate the MAC right here with `sign`)

-- | Prepare, authenticate and dispatch a request via the auto-generated BitMEX REST API.
dispatchRequest ::
      ( Produces req accept
      , MimeUnrender accept res
      , MimeType ct
      , MonadIO m
      )
   => BitMEX -> BitMEXRequest req ct res accept
   -> m (MimeResult res)
dispatchRequest config req@BitMEXRequest{..} = do
    time <- liftIO $ makeTimestamp <$> getPOSIXTime
    let restConfig = makeBitMEXRESTConfig config
        -- FIX ME! This should also be an `addAuthMethod` like the nonce was
        newReq = setHeader req [("api-expires", toByteString' time)]
    liftIO $ dispatchMime (connManager config) (generateAuthInfo config restConfig) newReq


-- FIX ME! Put these in the proper location
class ThreadSleep m where
    threadSleep :: Int -> m ()  -- threadDelay, generalized

instance ThreadSleep IO where
    threadSleep = threadDelay

-- | Retries 'retries' times waiting 1 second between attempts, while receiving error 503
retryOn503 :: (Monad m, ThreadSleep m) => Int -> m (MimeResult res) -> m (MimeResult res)
retryOn503 0       action = action -- no more retries
retryOn503 retries action = do
    res <- action
    case res of
        MimeResult {mimeResult = Left (MimeError {mimeErrorResponse = response})}
            | NH.Status{statusCode = 503} <- NH.responseStatus response  -> threadSleep 1000000 >> retryOn503 (retries - 1) action
        _ -> return res
