module BitMEXClient.WebSockets.Types.General
    ( Symbol(..)
    , Currency(..)
    , Side(..)
    , OrderType(..)
    , ExecutionInstruction(..)
    , ContingencyType(..)
    ) where

import           BitMEXClient.CustomPrelude
import           Prelude                    (Ord)

data Side
    = Buy
    | Sell
    deriving (Eq, Show, Generic)

instance FromJSON Side

instance ToJSON Side

data Currency
    = XBT
    | XBt
    | USD
    | A50
    | ADA
    | BCH
    | BFX
    | BLOCKS
    | BVOL
    | COIN
    | DAO
    | DASH
    | EOS
    | ETC
    | ETH
    | FCT
    | GNO
    | LSK
    | LTC
    | NEO
    | QTUM
    | REP
    | SEGWIT
    | SNT
    | WIN
    | XBC
    | XBJ
    | XBU
    | XLM
    | XLT
    | XMR
    | XRP
    | XTZ
    | ZEC
    | Total
    -- add
    | KRW
    | TRX
    | JPY
    deriving (Eq, Show, Generic)

instance ToJSON Currency

instance FromJSON Currency

data Symbol
    = XBTUSD
    | XBT7D_U105
    | XBTJPY
    | ADAZ19
    | BCHZ19
    | EOSZ19
    | ETHXBT
    | LTCZ19
    | TRXZ19
    | XRPZ19
    | XBTKRW
    | ETHUSD -- ?
    | XBTZ19
    | ETHZ19
    | XBT7D_D95
    | ADAH20
    | BCHH20
    | EOSH20
    | LTCH20
    | TRXH20
    | XRPH20
    | XBTH20
    | ETHH20
    | XBTM20
    deriving (Eq, Show, Ord, Generic)

instance ToJSON Symbol

instance FromJSON Symbol

data OrderType
    = Market
    | Limit
    | Stop
    | StopLimit
    | MarketIfTouched
    | LimitIfTouched
    | MarketWithLeftOverAsLimit
    | Pegged
    deriving (Eq, Show, Generic)

instance FromJSON OrderType

instance ToJSON OrderType

data ExecutionInstruction
    = ParticipateDoNotInitiate
    | AllOrNone
    | MarkPrice
    | IndexPrice
    | LastPrice
    | Close
    | ReduceOnly
    | Fixed
    deriving (Eq, Show, Generic)

instance FromJSON ExecutionInstruction

instance ToJSON ExecutionInstruction

data ContingencyType
    = OCO -- ^ One Cancels the Other
    | OTO -- ^ One Triggers the Other
    | OUOA -- ^ One Updates the Other Absoulute
    | OUOP -- ^ One Updates the Other Proportional
    deriving (Eq, Generic)

instance Show ContingencyType where
    show OCO  = "OneCancelsTheOther"
    show OTO  = "OneTriggersTheOther"
    show OUOA = "OneUpdatesTheOtherAbsolute"
    show OUOP = "OneUpdatesTheOtherProportional"

instance FromJSON ContingencyType

instance ToJSON ContingencyType
