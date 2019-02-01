{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

module PlanningGame.Data.Table.Msg (Msg(..)) where

import           Control.Monad        (mzero)
import           Data.Aeson.Types     (FromJSON (..), (.:))
import           Data.Aeson.Types     (Value (..))
import           Data.Text            (Text)

import           PlanningGame.Data.Game (Games (..), Vote)


data Msg
  = NewGame Text
  | FinishRound
  | NextRound Vote Text
  | Vote Vote
  | FinishGame Vote


instance FromJSON Msg where
  parseJSON (Object v) =
    (v .: "msg") >>= \(msg :: String) ->
       case msg of
         "NewGame" ->
           NewGame <$> (v .: "name")

         "FinishRound" ->
           pure FinishRound

         "NextRound" ->
           NextRound
             <$> (v .: "vote")
             <*> (v .: "name")

         "Vote" ->
           Vote <$> (v .: "vote")

         "FinishGame" ->
           FinishGame <$> (v .: "vote")

         _ ->
           mzero

  parseJSON _ = mzero