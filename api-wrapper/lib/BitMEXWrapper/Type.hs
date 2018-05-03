module BitMEXWrapper.Type
    ( BitMEXWrapperConfig(..)
    , BitMEXReader(..)
    ) where

import           Control.Monad.Reader
    ( Monad
    , MonadIO
    , MonadReader
    , ReaderT
    )
import qualified Data.ByteString      as SBS (ByteString)
import qualified Data.ByteString.Lazy as LBS (ByteString)
import           Data.Text            (Text)
import           Network.HTTP.Client  (Manager)
import           Prelude
    ( Applicative
    , Functor
    , IO
    )

data BitMEXWrapperConfig = BitMEXWrapperConfig
    { url        :: !LBS.ByteString
    , manager    :: !Manager
    , publicKey  :: !Text
    , privateKey :: !SBS.ByteString
    }

newtype BitMEXReader a = BitMEXReader
    { run :: (ReaderT BitMEXWrapperConfig IO) a
    } deriving ( Applicative
               , Functor
               , Monad
               , MonadIO
               , MonadReader BitMEXWrapperConfig
               )
