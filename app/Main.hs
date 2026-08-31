{-# LANGUAGE CPP #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Main
Description : Miso MVU front-end of the giacenza calculator
Copyright   : (c) 2026, paolino
License     : BSD-3-Clause

One MVU component: paste a CSV, confirm the date column, amount
column and number format, compute per-year saldo and giacenza. All
parsing and computation is delegated to the domain library; this
module owns no second parser and no second average-balance formula.

The wasm build exports @main@ to JavaScript as @hs_start@; the
interactive flag (used by repl-watch) reloads instead of starting.
-}
module Main (main) where

import Control.Monad.State (get)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Giacenza.Compute qualified as GC
import Giacenza.Parse qualified as GP
import Giacenza.Types
import Miso
import Miso.Html.Element qualified as H
import Miso.Html.Event qualified as E
import Miso.Html.Property qualified as P
import Miso.Lens (Lens, lens, (.=), (?=))
import Miso.String (fromMisoString, ms)
import Numeric (showFFloat)

{- | UI state: pasted text, detected headers, config in progress,
and either a result, an error, or idle.
-}
data Model = Model
    { modelPasted :: Text
    , modelHeaders :: [Text]
    , modelDateColumn :: Maybe Text
    , modelAmountColumn :: Maybe Text
    , modelFormat :: NumberFormat
    , modelOutcome :: Outcome
    }
    deriving (Show, Eq)

-- | Terminal state of one compute request.
data Outcome
    = Idle
    | Failure Text
    | Success Result
    deriving (Show, Eq)

data Action
    = CsvInputChanged Text
    | DateColumnChanged Text
    | AmountColumnChanged Text
    | NumberFormatChanged Text
    | ComputeRequested
    deriving (Show, Eq)

-- | Empty paste, no columns, European format, idle.
initialModel :: Model
initialModel =
    Model
        { modelPasted = ""
        , modelHeaders = []
        , modelDateColumn = Nothing
        , modelAmountColumn = Nothing
        , modelFormat = European
        , modelOutcome = Idle
        }

-- Miso record lenses over 'Model'.
lPasted :: Lens Model Text
lPasted = lens modelPasted (\m x -> m{modelPasted = x})

lHeaders :: Lens Model [Text]
lHeaders = lens modelHeaders (\m x -> m{modelHeaders = x})

lDateColumn :: Lens Model (Maybe Text)
lDateColumn = lens modelDateColumn (\m x -> m{modelDateColumn = x})

lAmountColumn :: Lens Model (Maybe Text)
lAmountColumn = lens modelAmountColumn (\m x -> m{modelAmountColumn = x})

lFormat :: Lens Model NumberFormat
lFormat = lens modelFormat (\m x -> m{modelFormat = x})

lOutcome :: Lens Model Outcome
lOutcome = lens modelOutcome (\m x -> m{modelOutcome = x})

#ifdef WASM
#ifndef INTERACTIVE
foreign export javascript "hs_start" main :: IO ()
#endif
#endif

-- | Wasm reactor entry point; reloadable under the interactive flag.
main :: IO ()
#ifdef INTERACTIVE
main = reload defaultEvents app
#else
main = startApp defaultEvents app
#endif

app :: App Model Action
app = component initialModel updateModel viewModel

updateModel :: Action -> Effect () () Model Action
updateModel = \case
    CsvInputChanged t -> do
        lPasted .= t
        lHeaders .= headersOf t
        lDateColumn .= firstHeader (headersOf t)
        lAmountColumn .= secondHeader (headersOf t)
        lOutcome .= Idle
    DateColumnChanged name ->
        lDateColumn .= Just name
    AmountColumnChanged name ->
        lAmountColumn .= Just name
    NumberFormatChanged "american" ->
        lFormat .= American
    NumberFormatChanged _ ->
        lFormat .= European
    ComputeRequested -> do
        m <- get
        lOutcome .= computeOutcome m

-- | Headers detected from the paste; [] when it does not parse.
headersOf :: Text -> [Text]
headersOf t = either (const []) GP.headers (GP.parseCsv t)

-- | Date column defaults to the first header (browser shape).
firstHeader :: [Text] -> Maybe Text
firstHeader hs = case hs of
    (h : _) -> Just h
    [] -> Nothing

-- | Amount column defaults to the second header (browser shape).
secondHeader :: [Text] -> Maybe Text
secondHeader hs = case hs of
    (_ : h : _) -> Just h
    _ -> Nothing

{- | One paste, one outcome: an error names its cause class and the
result table is not shown for the same submit.
-}
computeOutcome :: Model -> Outcome
computeOutcome m
    | T.null (T.strip (modelPasted m)) =
        Failure (renderParseError EmptyInput)
    | otherwise =
        case GP.parseCsv (modelPasted m) of
            Left e ->
                Failure (renderParseError e)
            Right table ->
                case (modelDateColumn m, modelAmountColumn m) of
                    (Just dc, Just ac) ->
                        let
                            cfg =
                                Config
                                    { configNumberFormat = modelFormat m
                                    , configDateColumn = dc
                                    , configAmountColumn = ac
                                    }
                        in
                            either
                                (Failure . renderParseError)
                                (Success . GC.yearResults)
                                (GP.extractMovements cfg table)
                    (Nothing, _) ->
                        Failure (renderParseError (MissingColumn "date"))
                    (_, Nothing) ->
                        Failure (renderParseError (MissingColumn "amount"))

viewModel :: () -> () -> Model -> View () Model Action
viewModel _ _ m =
    H.main_
        [P.class_ "giacenza"]
        [ H.h1_ [] ["Giacenza"]
        , H.p_
            [P.class_ "hint"]
            [ "Paste bank movements as CSV, confirm the columns and the number format, then compute."
            ]
        , H.textarea_
            [ P.class_ "paste"
            , P.cols_ "60"
            , P.rows_ "10"
            , P.placeholder_ "date,amount\n2023-01-01,100"
            , P.value_ (ms (modelPasted m))
            , E.onInput (CsvInputChanged . fromMisoString)
            ]
        , columnPicker
            "Date column"
            DateColumnChanged
            (modelDateColumn m)
            (modelHeaders m)
        , columnPicker
            "Amount column"
            AmountColumnChanged
            (modelAmountColumn m)
            (modelHeaders m)
        , H.select_
            [P.class_ "format", E.onChange (NumberFormatChanged . fromMisoString)]
            [ formatOption European "European (1.234,56)" (modelFormat m)
            , formatOption American "American (1,234.56)" (modelFormat m)
            ]
        , H.button_ [P.class_ "compute", E.onClick ComputeRequested] ["Compute"]
        , outcomeView (modelOutcome m)
        ]

-- | A select whose options are the detected headers.
columnPicker
    :: Text
    -> (Text -> Action)
    -> Maybe Text
    -> [Text]
    -> View () Model Action
columnPicker label mk selected hs =
    H.label_
        [P.class_ "column"]
        [ text (ms label)
        , H.select_
            [E.onChange (mk . fromMisoString)]
            [ H.option_
                [P.value_ (ms h), P.selected_ (Just h == selected)]
                [text (ms h)]
            | h <- hs
            ]
        ]

-- | One number-format option of the format select.
formatOption
    :: NumberFormat -> Text -> NumberFormat -> View () Model Action
formatOption f label current =
    H.option_
        [P.value_ (ms (formatName f)), P.selected_ (f == current)]
        [text (ms label)]

formatName :: NumberFormat -> Text
formatName European = "european"
formatName American = "american"

-- | Error node or result table (year, giacenza, saldo; two decimals).
outcomeView :: Outcome -> View () Model Action
outcomeView = \case
    Idle -> H.p_ [P.class_ "idle"] ["Paste data and press Compute."]
    Failure msg -> H.p_ [P.class_ "error"] [text (ms msg)]
    Success (Result mp) ->
        H.table_
            [P.class_ "results"]
            ( H.thead_
                []
                [ H.tr_
                    []
                    [ H.th_ [] ["Year"]
                    , H.th_ [] ["Giacenza"]
                    , H.th_ [] ["Saldo"]
                    ]
                ]
                : [ H.tr_
                    []
                    [ H.td_ [] [text (ms (show y))]
                    , H.td_ [] [text (ms (money (unGiacenza g)))]
                    , H.td_ [] [text (ms (money (unSaldo s)))]
                    ]
                  | (Year y, (s, g)) <- Map.toAscList mp
                  ]
            )

-- | Two-decimal amount rendering (showFFloat (Just 2)).
money :: Value -> Text
money (Value v) = T.pack (showFFloat (Just 2) v "")
