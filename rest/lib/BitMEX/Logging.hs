{-
   BitMEX API

   ## REST API for the BitMEX Trading Platform  [View Changelog](/app/apiChangelog)    #### Getting Started   ##### Fetching Data  All REST endpoints are documented below. You can try out any query right from this interface.  Most table queries accept `count`, `start`, and `reverse` params. Set `reverse=true` to get rows newest-first.  Additional documentation regarding filters, timestamps, and authentication is available in [the main API documentation](https://www.bitmex.com/app/restAPI).  *All* table data is available via the [Websocket](/app/wsAPI). We highly recommend using the socket if you want to have the quickest possible data without being subject to ratelimits.  ##### Return Types  By default, all data is returned as JSON. Send `?_format=csv` to get CSV data or `?_format=xml` to get XML data.  ##### Trade Data Queries  *This is only a small subset of what is available, to get you started.*  Fill in the parameters and click the `Try it out!` button to try any of these queries.  * [Pricing Data](#!/Quote/Quote_get)  * [Trade Data](#!/Trade/Trade_get)  * [OrderBook Data](#!/OrderBook/OrderBook_getL2)  * [Settlement Data](#!/Settlement/Settlement_get)  * [Exchange Statistics](#!/Stats/Stats_history)  Every function of the BitMEX.com platform is exposed here and documented. Many more functions are available.  ##### Swagger Specification  [⇩ Download Swagger JSON](swagger.json)    ## All API Endpoints  Click to expand a section.

   OpenAPI spec version: 2.0
   BitMEX API API version: 1.2.0
   Contact: support@bitmex.com
   Generated by Swagger Codegen (https://github.com/swagger-api/swagger-codegen.git)
-}

{-|
Module : BitMEX.Logging
Katip Logging functions
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module BitMEX.Logging where

import qualified Control.Exception.Safe as E
import qualified Control.Monad.IO.Class as P
import qualified Control.Monad.Trans.Reader as P
import qualified Data.Text as T
import qualified Lens.Micro as L
import qualified System.IO as IO

import Data.Text (Text)
import GHC.Exts (IsString(..))

import qualified Katip as LG

-- * Type Aliases (for compatibility)

-- | Runs a Katip logging block with the Log environment
type LogExecWithContext = forall m. P.MonadIO m =>
                                    LogContext -> LogExec m

-- | A Katip logging block
type LogExec m = forall a. LG.KatipT m a -> m a

-- | A Katip Log environment
type LogContext = LG.LogEnv

-- | A Katip Log severity
type LogLevel = LG.Severity

-- * default logger

-- | the default log environment
initLogContext :: IO LogContext
initLogContext = LG.initLogEnv "BitMEX" "dev"

-- | Runs a Katip logging block with the Log environment
runDefaultLogExecWithContext :: LogExecWithContext
runDefaultLogExecWithContext = LG.runKatipT

-- * stdout logger

-- | Runs a Katip logging block with the Log environment
stdoutLoggingExec :: LogExecWithContext
stdoutLoggingExec = runDefaultLogExecWithContext

-- | A Katip Log environment which targets stdout
stdoutLoggingContext :: LogContext -> IO LogContext
stdoutLoggingContext cxt = do
    handleScribe <- LG.mkHandleScribe LG.ColorIfTerminal IO.stdout (LG.permitItem LG.InfoS) LG.V2
    LG.registerScribe "stdout" handleScribe LG.defaultScribeSettings cxt

-- * stderr logger

-- | Runs a Katip logging block with the Log environment
stderrLoggingExec :: LogExecWithContext
stderrLoggingExec = runDefaultLogExecWithContext

-- | A Katip Log environment which targets stderr
stderrLoggingContext :: LogContext -> IO LogContext
stderrLoggingContext cxt = do
    handleScribe <- LG.mkHandleScribe LG.ColorIfTerminal IO.stderr (LG.permitItem LG.InfoS) LG.V2
    LG.registerScribe "stderr" handleScribe LG.defaultScribeSettings cxt

-- * Null logger

-- | Disables Katip logging
runNullLogExec :: LogExecWithContext
runNullLogExec le (LG.KatipT f) = P.runReaderT f (L.set LG.logEnvScribes mempty le)

-- * Log Msg

-- | Log a katip message
_log :: (Applicative m, LG.Katip m) => Text -> LogLevel -> Text -> m ()
_log src level msg = do
  LG.logMsg (fromString $ T.unpack src) level (LG.logStr msg)

-- * Log Exceptions

-- | re-throws exceptions after logging them
logExceptions
  :: (LG.Katip m, E.MonadCatch m, Applicative m)
  => Text -> m a -> m a
logExceptions src =
  E.handle
    (\(e :: E.SomeException) -> do
       _log src LG.ErrorS ((T.pack . show) e)
       E.throw e)

-- * Log Level

levelInfo :: LogLevel
levelInfo = LG.InfoS

levelError :: LogLevel
levelError = LG.ErrorS

levelDebug :: LogLevel
levelDebug = LG.DebugS

