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
import Miso.Lens (Lens, lens, (.=))
import Miso.String (MisoString, fromMisoString, ms)
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
    H.div_
        [P.class_ "giacenza"]
        [ H.header_
            [P.class_ "d-flex justify-content-center py-3"]
            [ H.ul_
                [P.class_ "nav nav-pills"]
                [ H.li_
                    [P.class_ "nav-item"]
                    [ H.a_
                        [ P.class_ "nav-link active"
                        , P.href_ "#"
                        ]
                        ["Calculator"]
                    ]
                , H.li_
                    [P.class_ "nav-item"]
                    [ H.a_
                        [ P.class_ "nav-link"
                        , P.href_
                            "https://paolino.github.io/giacenza/"
                        ]
                        ["Docs"]
                    ]
                ]
            ]
        , H.div_
            [P.class_ "container-fluid"]
            [ H.div_
                [P.class_ "main"]
                [ H.div_
                    [P.class_ "accordion"]
                    [ accordionItem
                        "paste"
                        "Paste CSV"
                        (pasteBody m)
                    , accordionItem
                        "report"
                        "Final report"
                        (outcomeView (modelOutcome m))
                    ]
                ]
            , H.div_
                [P.class_ "footer"]
                [footerView]
            ]
        ]

-- | One always-open accordion section, matching the production chrome.
accordionItem
    :: MisoString
    -> MisoString
    -> View () Model Action
    -> View () Model Action
accordionItem ident title body =
    H.div_
        [P.class_ "accordion-item"]
        [ H.h2_
            [P.class_ "accordion-header"]
            [ H.button_
                [ P.class_ "accordion-button"
                , P.type_ "button"
                ]
                [ H.h5_
                    [P.class_ "text-center mb-0"]
                    [text title]
                ]
            ]
        , H.div_
            [ P.class_ "accordion-collapse collapse show"
            , P.id_ ident
            ]
            [H.div_ [P.class_ "accordion-body"] [body]]
        ]

pasteBody :: Model -> View () Model Action
pasteBody m =
    H.div_
        []
        [ H.p_
            [P.class_ "hint text-body-secondary"]
            [ "Paste bank movements as CSV, confirm the columns and the number format, then compute."
            ]
        , H.div_
            [P.class_ "mb-3"]
            [ H.label_
                [P.class_ "form-label"]
                ["CSV"]
            , H.textarea_
                [ P.class_ "paste form-control font-monospace"
                , P.rows_ "10"
                , P.placeholder_
                    "date,amount\n2023-01-01,100"
                , P.value_ (ms (modelPasted m))
                , E.onInput
                    (CsvInputChanged . fromMisoString)
                ]
            ]
        , H.div_
            [P.class_ "row g-3 mb-3"]
            [ H.div_
                [P.class_ "col-md-4"]
                [ columnPicker
                    "Date column"
                    DateColumnChanged
                    (modelDateColumn m)
                    (modelHeaders m)
                ]
            , H.div_
                [P.class_ "col-md-4"]
                [ columnPicker
                    "Amount column"
                    AmountColumnChanged
                    (modelAmountColumn m)
                    (modelHeaders m)
                ]
            , H.div_
                [P.class_ "col-md-4"]
                [ H.label_
                    [P.class_ "form-label"]
                    ["Number format"]
                , H.select_
                    [ P.class_ "format form-select"
                    , E.onChange
                        ( NumberFormatChanged
                            . fromMisoString
                        )
                    ]
                    [ formatOption
                        European
                        "European (1.234,56)"
                        (modelFormat m)
                    , formatOption
                        American
                        "American (1,234.56)"
                        (modelFormat m)
                    ]
                ]
            ]
        , H.button_
            [ P.class_ "compute btn btn-primary"
            , P.type_ "button"
            , E.onClick ComputeRequested
            ]
            ["Compute"]
        ]

footerView :: View () Model Action
footerView =
    H.footer_
        [ P.class_
            "d-md-flex flex-wrap justify-content-between align-items-center py-3 ms-4 border-top"
        ]
        [ H.div_
            [P.class_ "col d-md-flex align-items-center"]
            [ H.ul_
                [P.class_ "nav flex-column"]
                [ H.li_
                    [P.class_ "nav-item mb-2"]
                    [ "© 2023-2026 Paolo Veronelli, Lambdasistemi"
                    ]
                , H.li_
                    [P.class_ "nav-item mb-2"]
                    [ H.span_ [] ["Source code on "]
                    , H.a_
                        [ P.href_
                            "https://github.com/paolino/giacenza-miso"
                        ]
                        ["GitHub"]
                    ]
                ]
            ]
        , H.div_
            [P.class_ "col d-md-flex align-items-center"]
            [ H.div_
                [P.class_ "mb-3 mb-md-0 text-body-secondary"]
                [ "Powered by Haskell, Miso, GHC wasm32-wasi, Bootstrap"
                ]
            ]
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
        [P.class_ "column form-label w-100"]
        [ text (ms label)
        , H.select_
            [ P.class_ "form-select"
            , E.onChange (mk . fromMisoString)
            ]
            [ H.option_
                [ P.value_ (ms h)
                , P.selected_ (Just h == selected)
                ]
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
    Idle ->
        H.p_
            [P.class_ "idle text-body-secondary"]
            ["Paste data and press Compute."]
    Failure msg ->
        H.div_
            [P.class_ "error alert alert-danger"]
            [ H.h5_ [] ["Error in the request"]
            , H.p_ [P.class_ "mb-0"] [text (ms msg)]
            ]
    Success (Result mp)
        | Map.null mp ->
            H.p_
                [P.class_ "idle text-body-secondary"]
                ["No results."]
        | otherwise ->
            H.table_
                [P.class_ "results table table-striped"]
                [ H.thead_
                    []
                    [ H.tr_
                        []
                        [ H.th_ [P.class_ "text-end"] ["Year"]
                        , H.th_ [P.class_ "text-end"] ["Average"]
                        , H.th_ [P.class_ "text-end"] ["Last balance"]
                        ]
                    ]
                , H.tbody_
                    []
                    [ H.tr_
                        []
                        [ H.td_
                            [P.class_ "text-end"]
                            [text (ms (show y))]
                        , H.td_
                            [P.class_ "text-end"]
                            [text (ms (money (unGiacenza g)))]
                        , H.td_
                            [P.class_ "text-end"]
                            [text (ms (money (unSaldo s)))]
                        ]
                    | (Year y, (s, g)) <- Map.toAscList mp
                    ]
                ]

-- | Two-decimal amount rendering (showFFloat (Just 2)).
money :: Value -> Text
money (Value v) = T.pack (showFFloat (Just 2) v "")
