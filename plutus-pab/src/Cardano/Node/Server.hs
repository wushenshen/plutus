{-# LANGUAGE FlexibleContexts   #-}
{-# LANGUAGE NamedFieldPuns     #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings  #-}
{-# LANGUAGE TypeApplications   #-}

module Cardano.Node.Server
    ( main
    ) where

import           Cardano.BM.Data.Trace            (Trace)
import           Cardano.Node.API                 (API)
import           Cardano.Node.Mock
import           Cardano.Node.Types
import qualified Cardano.Protocol.Socket.Client   as Client
import qualified Cardano.Protocol.Socket.Server   as Server
import           Control.Concurrent               (MVar, forkIO, newMVar)
import           Control.Concurrent.Availability  (Availability, available)
import           Control.Monad                    (void)
import           Control.Monad.Freer.Delay        (delayThread, handleDelayEffect)
import           Control.Monad.Freer.Extras.Log   (logInfo)
import           Control.Monad.IO.Class           (liftIO)
import           Data.Function                    ((&))
import qualified Data.Map.Strict                  as Map
import           Data.Proxy                       (Proxy (Proxy))
import           Data.Time.Clock.POSIX            (posixSecondsToUTCTime)
import           Data.Time.Units                  (Second)
import qualified Ledger.Ada                       as Ada
import           Ledger.TimeSlot                  (SlotConfig (SlotConfig, scSlotLength, scZeroSlotTime))
import qualified Network.Wai.Handler.Warp         as Warp
import           Plutus.PAB.Arbitrary             ()
import qualified Plutus.PAB.Monitoring.Monitoring as LM
import           Servant                          (Application, hoistServer, serve, (:<|>) ((:<|>)))
import           Servant.Client                   (BaseUrl (baseUrlPort))

app ::
    Trace IO MockServerLogMsg
 -> Client.TxSendHandle
 -> MVar AppState
 -> Application
app trace clientHandler stateVar =
    serve (Proxy @API) $
    hoistServer
        (Proxy @API)
        (liftIO . processChainEffects trace clientHandler stateVar)
        (healthcheck :<|>
         (genRandomTx :<|>
          consumeEventHistory stateVar))

data Ctx = Ctx { serverHandler :: Maybe Server.ServerHandler
               , txSendHandle  :: Client.TxSendHandle
               , serverState   :: MVar AppState
               , mockTrace     :: Trace IO MockServerLogMsg
               }

main :: Trace IO MockServerLogMsg -> MockServerConfig -> MockServerMode -> Availability -> IO ()
main trace MockServerConfig { mscBaseUrl
                            , mscRandomTxInterval
                            , mscKeptBlocks
                            , mscSlotConfig
                            , mscInitialTxWallets
                            , mscSocketPath } withoutMockServer availability = LM.runLogEffects trace $ do

    -- make initial distribution of 1 billion Ada to all configured wallets
    let dist = Map.fromList $ zip mscInitialTxWallets (repeat (Ada.adaValueOf 1000_000_000))
    initialState <- initialChainState dist
    let appState = AppState
            { _chainState = initialState
            , _eventHistory = mempty
            }
    serverHandler <- case withoutMockServer of
        WithoutMockServer -> pure Nothing
        WithMockServer    -> Just <$> (liftIO $ Server.runServerNode trace mscSocketPath mscKeptBlocks (_chainState appState))
    serverState   <- liftIO $ newMVar appState
    handleDelayEffect $ delayThread (2 :: Second)
    clientHandler <- liftIO $ Client.runTxSender mscSocketPath

    let ctx = Ctx { serverHandler = serverHandler
                  , txSendHandle  = clientHandler
                  , serverState   = serverState
                  , mockTrace     = trace
                  }

    runSlotCoordinator ctx
    maybe (logInfo NoRandomTxGeneration) (runRandomTxGeneration ctx) mscRandomTxInterval

    logInfo $ StartingMockServer $ baseUrlPort mscBaseUrl
    liftIO $ Warp.runSettings warpSettings $ app trace clientHandler serverState

        where
            warpSettings = Warp.defaultSettings & Warp.setPort (baseUrlPort mscBaseUrl) & Warp.setBeforeMainLoop (available availability)

            runRandomTxGeneration Ctx { txSendHandle , serverState , mockTrace } randomTxInterval = do
                    logInfo StartingRandomTx
                    void $ liftIO $ forkIO $ transactionGenerator mockTrace randomTxInterval txSendHandle serverState

            runSlotCoordinator (Ctx (Just serverHandler) _ _ _)  = do
                let SlotConfig{scZeroSlotTime, scSlotLength} = mscSlotConfig
                logInfo $ StartingSlotCoordination (posixSecondsToUTCTime $ realToFrac scZeroSlotTime)
                                                   (fromInteger scSlotLength :: Second)
                void $ liftIO $ forkIO $ slotCoordinator mscSlotConfig serverHandler
            -- Don't start the coordinator if we don't start the mock server.
            runSlotCoordinator _ = pure ()
