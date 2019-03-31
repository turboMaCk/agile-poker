module Page.Table exposing (Model, Msg, init, leave, subscriptions, update, view)

import Browser.Dom as Dom
import Browser.Navigation as Navigation exposing (Key)
import Cmd.Extra as Cmd
import Component
import Css
import Data exposing (ApiError, Game(..), Player, TableError(..), Vote(..))
import Dict exposing (Dict)
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attrs
import Html.Styled.Events as Events
import Maybe.Extra as Maybe
import Page.Table.Card as Card exposing (Side(..))
import Page.Table.Players as Players exposing (PlayerVote(..))
import Page.Table.Stream as Stream exposing (Event(..), StreamError)
import Set
import Set.Any as AnySet
import Task
import Theme
import Url.Builder as Url


{-| @TODO: Think if tableError and me shouldn't be
single Result type
-}
type alias Model =
    { tableId : String
    , me : Maybe Player
    , banker : Maybe Player
    , players : Dict String Player
    , tableError : Maybe (ApiError TableError)
    , myVote : Maybe Vote
    , game : Game
    , gameName : Maybe String
    , nextGameName : String
    }


init : String -> String -> ( Model, Cmd Msg )
init token id =
    ( { tableId = id
      , me = Nothing
      , banker = Nothing
      , players = Dict.empty
      , tableError = Nothing
      , myVote = Nothing
      , game = NotStarted
      , gameName = Just ""
      , nextGameName = "Task-1"
      }
    , Data.getMe token id Me
    )


type Msg
    = Me (Result (ApiError TableError) Player)
    | NoOp
    | Event (Result StreamError Event)
    | Send Stream.Msg
    | Vote Vote
    | SetName String
    | NewGame String
    | FinishGame
    | ClearMyVote


leave : () -> Cmd msg
leave () =
    Stream.disconnect ()


allPlayers : Model -> Dict String Player
allPlayers model =
    Maybe.unwrap model.players (\b -> Dict.insert b.name b model.players) model.banker


focusNameField : ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
focusNameField ( model, cmd ) =
    -- @TODO: add check on game state?
    if amIBanker model then
        ( model, cmd )
            |> Cmd.add (Task.attempt (always NoOp) <| Dom.focus nameFieldId)

    else
        ( model, cmd )


playerVoted : Player -> Model -> Model
playerVoted player model =
    case model.game of
        Voting data ->
            { model
                | game =
                    Voting
                        { data
                            | maskedVotes =
                                Set.insert player.name data.maskedVotes
                        }
            }

        _ ->
            model


updatePlayer : Player -> Model -> Model
updatePlayer player model =
    if Just player.name == Maybe.map .name model.banker then
        { model | banker = Just player }

    else
        { model | players = Dict.insert player.name player model.players }


amIBanker : Model -> Bool
amIBanker { me, banker } =
    case ( me, banker ) of
        ( Just p1, Just p2 ) ->
            p1.name == p2.name

        _ ->
            False


update : Key -> Msg -> Model -> ( Model, Cmd Msg )
update navigationKey msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        Me result ->
            case result of
                Ok player ->
                    ( { model | me = Just player }
                    , Stream.connect model.tableId
                    )

                Err err ->
                    ( { model | tableError = Just err }
                    , if Data.errorIs PlayerNotFound err then
                        Navigation.pushUrl navigationKey <|
                            Url.absolute [ "table", model.tableId, "join" ] []

                      else
                        Cmd.none
                    )

        Event result ->
            case result of
                Ok e ->
                    handleEvent e model

                Err _ ->
                    -- @TODO: handle errors
                    -- Translate StreamError to ApiError TableError?
                    ( model, Cmd.none )

        Send streamMsg ->
            ( model, Stream.sendMsg streamMsg )

        Vote vote ->
            if Data.isVoting model.game then
                { model | myVote = Just vote }
                    |> Cmd.with (Stream.sendMsg <| Stream.Vote vote)

            else if Data.isRoundFinished model.game && amIBanker model then
                ( { model | gameName = Just "", myVote = Just vote }, Cmd.none )
                    |> focusNameField

            else
                ( model, Cmd.none )

        SetName str ->
            ( { model | gameName = Just str }, Cmd.none )

        NewGame str ->
            case model.game of
                NotStarted ->
                    { model | gameName = Nothing }
                        |> Cmd.with (Stream.sendMsg <| Stream.NewGame str)

                RoundFinished _ ->
                    case model.myVote of
                        Just vote ->
                            { model | gameName = Nothing }
                                |> Cmd.with (Stream.sendMsg <| Stream.NextGame str vote)

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        FinishGame ->
            case model.myVote of
                Just vote ->
                    { model | gameName = Nothing }
                        |> Cmd.with (Stream.sendMsg <| Stream.Finish vote)

                Nothing ->
                    ( model, Cmd.none )

        ClearMyVote ->
            ( { model | myVote = Nothing }, Cmd.none )



-- NoOp


handleEvent : Event -> Model -> ( Model, Cmd Msg )
handleEvent event model =
    case event of
        PlayerJoin player ->
            ( updatePlayer player model
            , Cmd.none
            )

        PlayerStatusUpdate player ->
            ( updatePlayer player model
            , Cmd.none
            )

        SyncTableState ( table, game ) nextGameName ->
            ( { model
                | tableId = table.id
                , banker = Just table.banker
                , nextGameName = nextGameName
                , players =
                    List.map (\player -> ( player.name, player )) table.players
                        |> Dict.fromList
                , game = game
              }
            , Cmd.none
            )
                |> focusNameField

        GameStarted game ->
            ( { model | game = game, myVote = Nothing }, Cmd.none )

        VoteAccepted player ->
            ( playerVoted player model, Cmd.none )

        VotingEnded game nextGameName ->
            ( { model
                | game = game
                , myVote = Nothing
                , nextGameName = nextGameName
              }
            , Cmd.none
            )

        GameEnded game ->
            ( { model | game = game }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Stream.observe Event


viewTable : (Vote -> Side) -> Html Msg
viewTable toSide =
    Html.styled Html.div [ Css.marginLeft <| Css.px -12 ] [] <|
        Card.table toSide Vote


viewVoting : Model -> Html Msg
viewVoting model =
    let
        toSide vote =
            case model.myVote of
                Just myVote ->
                    if vote == myVote then
                        Front

                    else
                        Back

                Nothing ->
                    Front
    in
    viewTable toSide


viewPlayerVotes : Dict String Vote -> Html Msg
viewPlayerVotes dict =
    let
        voteSet =
            Dict.values dict
                |> AnySet.fromList Data.voteToInt

        toSide vote =
            if AnySet.member vote voteSet then
                Front

            else
                Back
    in
    viewTable toSide


nameFieldId : String
nameFieldId =
    "game-name-field"


setNameView : Model -> Html Msg
setNameView model =
    let
        name =
            Maybe.withDefault "" model.gameName
    in
    if amIBanker model then
        Component.nameForm
            { onInput = SetName
            , onSubmit = NewGame name
            , submitTxt =
                if Data.isNewGame model.game then
                    "Start"

                else
                    "Next Task"
            , value = name
            , inputId = nameFieldId
            , labelTxt = "Name the task"
            , placeHolder = model.nextGameName
            , above =
                if Data.isNewGame model.game then
                    Html.styled Html.h2 [ Theme.heading ] [] [ Html.text "First Task" ]

                else
                    Html.styled Html.h2 [ Theme.heading ] [] [ Html.text "Next Task" ]
            , otherBtns =
                if Data.isNewGame model.game then
                    []

                else
                    [ Html.styled Html.button
                        [ Theme.secondaryBtn
                        , Css.marginTop <| Css.px 12
                        ]
                        [ Events.onClick ClearMyVote ]
                        [ Html.text "Back" ]
                    , Html.styled Html.button
                        [ Theme.secondaryBtn
                        , Css.marginTop <| Css.px 12
                        ]
                        [ Events.onClick FinishGame
                        , Attrs.type_ "button"
                        ]
                        [ Html.text "Finish Game" ]
                    ]
            , errorsView = Nothing
            }

    else
        Html.styled Html.div
            [ Css.displayFlex
            , Css.height <| Css.px 400
            , Css.maxHeight <| Css.pct 100
            , Css.justifyContent Css.center
            , Css.alignItems Css.center
            ]
            []
            [ Html.styled Html.span
                [ Theme.highlight
                , Theme.shaking 5
                , Css.fontSize <| Css.px 40
                ]
                []
                [ Html.text "Wait till game starts..." ]
            ]


viewOverviewTable : Dict String a -> { b | playerVotes : List ( String, Dict String Vote ), results : Dict String Vote } -> Html msg
viewOverviewTable players_ { playerVotes, results } =
    let
        toString =
            String.fromInt << Data.voteToInt

        voteCell votes name =
            Html.styled Html.td
                [ tdStyle ]
                []
                [ Html.text <| Maybe.unwrap "?" toString <| Dict.get name votes ]

        players =
            Dict.keys players_

        tdStyle =
            Css.batch
                [ Css.textAlign Css.center
                , Css.padding2 (Css.px 6) (Css.px 6)
                , Css.fontWeight <| Css.int 200
                ]

        thStyle =
            Css.batch
                [ tdStyle
                , Css.fontWeight <| Css.int 400
                ]

        highlighted =
            Css.batch
                [ tdStyle
                , Css.fontWeight <| Css.int 700
                ]

        viewTr ( name, votes ) =
            Html.styled Html.tr [ Css.borderTop3 (Css.px 1) Css.solid (Css.hex "#cccccc") ] [] <|
                [ Html.styled Html.td
                    [ highlighted
                    , Css.textAlign Css.left
                    ]
                    []
                    [ Html.text name ]
                , Html.styled Html.td [ highlighted ] [] <|
                    [ Html.text <|
                        Maybe.unwrap "?" toString <|
                            Dict.get name results
                    ]
                ]
                    ++ List.map (voteCell votes) players

        tBody =
            Html.tbody [] <|
                List.map viewTr playerVotes
    in
    Html.styled Html.table
        [ Css.minWidth <| Css.pct 100
        , Css.fontSize <| Css.px 16
        , Css.borderCollapse Css.collapse
        ]
        []
        [ Html.thead [] <|
            [ Html.tr [] <|
                [ Html.styled Html.th [ thStyle, Css.textAlign Css.left ] [] [ Html.text "Task" ]
                , Html.styled Html.th [ thStyle ] [] [ Html.text "Agreed" ]
                ]
                    ++ List.map (\n -> Html.styled Html.th [ thStyle ] [] [ Html.text n ]) players
            ]
        , tBody
        ]


viewGame : Model -> Html Msg
viewGame model =
    let
        inner =
            case model.game of
                NotStarted ->
                    let
                        ( shake, text ) =
                            if amIBanker model then
                                ( True, "Start the game when ready..." )

                            else
                                ( False, "Prepare for start!" )
                    in
                    [ Theme.highlightedHeading shake [ Html.text text ]
                    , setNameView model
                    ]

                Voting _ ->
                    let
                        shake =
                            model.myVote == Nothing
                    in
                    [ Theme.highlightedHeading shake [ Html.text "Pick your card!" ]
                    , viewVoting model
                    , Html.br [] []
                    , if amIBanker model then
                        Html.styled Html.button
                            [ Theme.secondaryBtn ]
                            [ Events.onClick <| Send Stream.FinishRound ]
                            [ Html.text "Finish Round" ]

                      else
                        Html.text ""
                    ]

                RoundFinished { playerVotes } ->
                    if amIBanker model && model.myVote /= Nothing then
                        -- Banker definitng new ticket
                        [ Theme.highlightedHeading False [ Html.text "Set next taks OR finish the game!" ]
                        , setNameView model
                        ]

                    else if amIBanker model then
                        -- Banker chossing agreed estimation
                        [ Theme.highlightedHeading True [ Html.text "Choose agreed extimation!" ]
                        , viewPlayerVotes playerVotes
                        , Html.br [] []
                        , Html.styled Html.button
                            [ Theme.secondaryBtn ]
                            [ Events.onClick <| Send Stream.Restart ]
                            [ Html.text "Restart Round" ]
                        ]

                    else
                        --Player waiting for banker
                        [ Theme.highlightedHeading False [ Html.text "Wait for the next ticket!" ]
                        , viewPlayerVotes playerVotes
                        ]

                Overview data ->
                    [ Html.styled Html.h2 [ Theme.heading, Css.marginTop Css.zero ] [] [ Html.text "Game results" ]
                    , viewOverviewTable (allPlayers model) data
                    ]
    in
    Html.styled Html.div [ Css.width <| Css.px 835 ] [] inner


viewCurrentGame : Game -> Html msg
viewCurrentGame game =
    let
        headlineStyle =
            Css.batch
                [ Css.margin2 (Css.px 12) Css.zero
                , Css.fontSize <| Css.px 27
                ]

        headline =
            Html.styled Html.h2

        showName name =
            headline [ headlineStyle ]
                []
                [ Html.styled Html.span
                    [ Css.fontWeight <| Css.int 200
                    , Css.display Css.block
                    , Css.fontSize <| Css.px 20
                    , Css.marginBottom <| Css.px 6
                    ]
                    []
                    [ Html.text "Estimating task:" ]
                , Html.text name
                ]
    in
    case game of
        NotStarted ->
            headline
                [ headlineStyle
                , Css.fontWeight <| Css.int 200
                , Css.fontSize <| Css.px 20
                ]
                []
                [ Html.text "Game hasn't started." ]

        Voting { name } ->
            showName name

        RoundFinished { name } ->
            showName name

        Overview _ ->
            Html.text ""


viewPointsSoFar : Game -> Html msg
viewPointsSoFar game =
    let
        showPoints txt int =
            Html.styled Html.h3
                [ Css.margin Css.zero
                , Css.fontSize <| Css.px 37
                ]
                []
                [ Html.styled Html.span
                    [ Css.fontWeight <| Css.int 200
                    , Css.fontSize <| Css.px 20
                    , Css.display Css.block
                    ]
                    []
                    [ Html.text txt ]
                , Html.text <| String.fromInt int
                ]
    in
    case game of
        NotStarted ->
            Html.text ""

        Voting { totalPoints } ->
            showPoints "Points so far:" totalPoints

        RoundFinished { totalPoints } ->
            showPoints "Points so far:" totalPoints

        Overview { totalPoints } ->
            showPoints "Total points:" totalPoints


view : Model -> Html Msg
view model =
    let
        isMe { name } =
            Maybe.unwrap False ((==) name << .name) model.me

        toVote player =
            case model.game of
                NotStarted ->
                    Hidden

                Voting { maskedVotes } ->
                    if Set.member player.name maskedVotes then
                        Unknown

                    else
                        Hidden

                RoundFinished { playerVotes } ->
                    Dict.get player.name playerVotes
                        |> Maybe.unwrap Unknown Voted

                Overview _ ->
                    Hidden
    in
    Component.withTableNotFound model.tableError <|
        Html.styled Html.div
            [ Css.displayFlex
            , Css.justifyContent Css.spaceBetween
            ]
            []
            [ viewGame model
            , Html.styled Html.aside
                [ Css.width <| Css.px 250
                ]
                []
                [ viewCurrentGame model.game
                , viewPointsSoFar model.game
                , Players.view isMe toVote model.banker model.players
                ]
            ]
