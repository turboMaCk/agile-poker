{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE NamedFieldPuns      #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators       #-}


module PlanningGame.Api
  ( ServerState
  , initState
  , app
  , tables
  ) where

import           Control.Concurrent           (MVar)
import           Control.Monad.IO.Class       (MonadIO, liftIO)
import           Data.Text                    (Text)
import           Servant
import           Servant.API.WebSocket        (WebSocket)

import qualified Control.Concurrent           as Concurrent
import qualified Network.WebSockets           as WS

import           PlanningGame.Api.Authorization
import           PlanningGame.Api.PlayerInfo

import           PlanningGame.Data
import           PlanningGame.State

import qualified PlanningGame.Api.Middleware as Middleware
import qualified PlanningGame.Api.Error as Error
import qualified PlanningGame.Data.Table as Table


-- API


type Api = "status"                                :> Get  '[JSON] Text
      :<|> "session"                               :> Post '[JSON] SessionJSON
      :<|> "session" :> AuthProtect "header"       :> Get  '[JSON] SessionJSON
      :<|> "tables"  :> AuthProtect "header"       :> ReqBody '[JSON] PlayerInfo      :> Post '[JSON] Table
      :<|> "tables"  :> AuthProtect "header"       :> Capture "tableid" (Id TableId)  :> "join"
                     :> ReqBody '[JSON] PlayerInfo :> Post '[JSON] Table
      :<|> "tables"  :> AuthProtect "header"       :> Capture "tableid" (Id TableId)  :> "me"
                                                   :> Get '[JSON] Player
      :<|> "tables"  :> AuthProtect "cookie"       :> Capture "tableid" (Id TableId)  :> "stream" :> WebSocket


api :: Proxy Api
api = Proxy


-- Server


genContext :: MVar Sessions -> Context (SessionHeaderAuth : SessionCookieAuth ': '[])
genContext state =
  authHeaderHandler state :. authCookieHandler state :. EmptyContext


server :: ServerState -> Server Api
server state = status
           :<|> createSession
           :<|> getSession'
           :<|> createTableHandler
           :<|> joinTableHandler
           :<|> meHandler
           :<|> streamTableHandler

  where
    status :: Handler Text
    status = pure "OK"

    createSession :: Handler SessionJSON
    createSession =
      pure . SessionJSON =<<
        (liftIO $ Concurrent.modifyMVar (sessions state) addSession)

    getSession' :: (HeaderAuth Session) -> Handler SessionJSON
    getSession' =
      pure . SessionJSON . unHeaderAuth

    createTableHandler :: (HeaderAuth Session) -> PlayerInfo -> Handler Table
    createTableHandler (HeaderAuth session) PlayerInfo { playerInfoName } = do
      res <- liftIO $ Concurrent.modifyMVar (tables state)
                $ Table.create session playerInfoName

      either Error.respond pure res

    joinTableHandler :: (HeaderAuth Session) -> Id TableId -> PlayerInfo -> Handler Table
    joinTableHandler (HeaderAuth session) id' PlayerInfo { playerInfoName } = do
      tables <- liftIO $ Concurrent.readMVar (tables state)
      tableRes <- liftIO $ Table.join session id' playerInfoName tables

      either Error.respond pure tableRes

    meHandler :: (HeaderAuth Session) -> Id TableId -> Handler Player
    meHandler (HeaderAuth session) tableId = do
      ts <- liftIO $ Concurrent.readMVar (tables state)
      playerRes <- liftIO $ Table.getPlayer session tableId ts

      either Error.respond pure playerRes

    streamTableHandler :: MonadIO m => (CookieAuth Session) -> Id TableId -> WS.Connection -> m ()
    streamTableHandler (CookieAuth session) id' conn =
      liftIO $ Table.streamHandler (tables state) session id' conn


app :: ServerState -> Application
app state = Middleware.static $
    serveWithContext api (genContext $ sessions state) $
    server state
