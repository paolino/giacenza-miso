{-# LANGUAGE CPP #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Main
Description : Miso MVU front-end of the giacenza calculator
Copyright   : (c) 2026, paolino
License     : BSD-3-Clause

One MVU component: paste one or more CSVs, confirm columns and
number format per statement, see per-statement results and an
aggregated final report. Parsing and computation stay in the
domain library.

The wasm build exports @main@ to JavaScript as @hs_start@; the
interactive flag (used by repl-watch) reloads instead of starting.
-}
module Main (main) where

import Control.Monad (forM_, void)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
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
import Numeric (showFFloat)
import Prelude hiding ((!!))

-- | Draft in the Add-files section (not yet a statement).
data Draft = Draft
    { draftPasted :: Text
    , draftHeaders :: [Text]
    , draftDateColumn :: Maybe Text
    , draftAmountColumn :: Maybe Text
    , draftFormat :: NumberFormat
    , draftError :: Maybe Text
    }
    deriving (Show, Eq)

-- | One pasted CSV in the original multi-statement workflow.
data Statement = Statement
    { stmtId :: Int
    , stmtName :: Text
    , stmtPasted :: Text
    , stmtHeaders :: [Text]
    , stmtDateColumn :: Maybe Text
    , stmtAmountColumn :: Maybe Text
    , stmtFormat :: NumberFormat
    , stmtOutcome :: Outcome
    , stmtEditing :: Bool
    }
    deriving (Show, Eq)

-- | Which nav pill is showing.
data Page
    = StatementsPage
    | AboutPage
    deriving (Show, Eq)

-- | Page state: add-files draft plus zero or more statements.
data Model = Model
    { modelDraft :: Draft
    , modelStatements :: [Statement]
    , modelNextId :: Int
    , modelPage :: Page
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
    | FilesChosen JSVal
    | FileLoaded Text Text
    | ShowPage Page
    | StmtDate Int Text
    | StmtAmount Int Text
    | StmtFormat Int Text
    | Analyze Int
    | Reconfigure Int
    | Delete Int
    | ReconfigureAll
    | DeleteAll

emptyDraft :: Draft
emptyDraft =
    Draft
        { draftPasted = ""
        , draftHeaders = []
        , draftDateColumn = Nothing
        , draftAmountColumn = Nothing
        , draftFormat = European
        , draftError = Nothing
        }

-- | Empty add-files draft, no statements.
initialModel :: Model
initialModel =
    Model
        { modelDraft = emptyDraft
        , modelStatements = []
        , modelNextId = 1
        , modelPage = StatementsPage
        }

lPage :: Lens Model Page
lPage = lens modelPage (\m x -> m{modelPage = x})

lDraft :: Lens Model Draft
lDraft = lens modelDraft (\m x -> m{modelDraft = x})

lStatements :: Lens Model [Statement]
lStatements =
    lens modelStatements (\m x -> m{modelStatements = x})

lNextId :: Lens Model Int
lNextId = lens modelNextId (\m x -> m{modelNextId = x})

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
    CsvInputChanged t ->
        lDraft
            .= emptyDraft
                { draftPasted = t
                , draftHeaders = hs
                , draftDateColumn = firstHeader hs
                , draftAmountColumn = secondHeader hs
                , draftFormat = European
                }
      where
        hs = headersOf t
    DateColumnChanged name -> do
        m <- get
        lDraft .= (modelDraft m){draftDateColumn = Just name}
    AmountColumnChanged name -> do
        m <- get
        lDraft .= (modelDraft m){draftAmountColumn = Just name}
    NumberFormatChanged "american" -> do
        m <- get
        lDraft .= (modelDraft m){draftFormat = American}
    NumberFormatChanged _ -> do
        m <- get
        lDraft .= (modelDraft m){draftFormat = European}
    FilesChosen input ->
        withSink $ \sink -> do
            fs <- chosenFiles input
            forM_ fs (readCsvFile sink)
            setValue input ("" :: MisoString)
    FileLoaded name content -> do
        m <- get
        let
            hs = headersOf content
            i = modelNextId m
            stmt =
                Statement
                    { stmtId = i
                    , stmtName = name
                    , stmtPasted = content
                    , stmtHeaders = hs
                    , stmtDateColumn = firstHeader hs
                    , stmtAmountColumn = secondHeader hs
                    , stmtFormat = draftFormat (modelDraft m)
                    , stmtOutcome = Idle
                    , stmtEditing = True
                    }
        lStatements .= modelStatements m <> [stmt]
        lNextId .= i + 1
    ShowPage p ->
        lPage .= p
    ComputeRequested -> do
        m <- get
        case computeDraft (modelDraft m) of
            Left err ->
                lDraft
                    .= (modelDraft m){draftError = Just err}
            Right (_, result) -> do
                let
                    d = modelDraft m
                    i = modelNextId m
                    stmt =
                        Statement
                            { stmtId = i
                            , stmtName = "CSV " <> T.pack (show i)
                            , stmtPasted = draftPasted d
                            , stmtHeaders = draftHeaders d
                            , stmtDateColumn = draftDateColumn d
                            , stmtAmountColumn = draftAmountColumn d
                            , stmtFormat = draftFormat d
                            , stmtOutcome = Success result
                            , stmtEditing = False
                            }
                lStatements .= modelStatements m <> [stmt]
                lNextId .= i + 1
                lDraft .= emptyDraft{draftFormat = draftFormat d}
    StmtDate i name ->
        modifyStmt i (\s -> s{stmtDateColumn = Just name})
    StmtAmount i name ->
        modifyStmt i (\s -> s{stmtAmountColumn = Just name})
    StmtFormat i "american" ->
        modifyStmt i (\s -> s{stmtFormat = American})
    StmtFormat i _ ->
        modifyStmt i (\s -> s{stmtFormat = European})
    Analyze i -> do
        m <- get
        lStatements
            .= [ if stmtId s == i
                then s{stmtOutcome = analyzeStatement s, stmtEditing = False}
                else s
               | s <- modelStatements m
               ]
    Reconfigure i ->
        modifyStmt i (\s -> s{stmtEditing = True})
    Delete i -> do
        m <- get
        lStatements .= filter ((/= i) . stmtId) (modelStatements m)
    ReconfigureAll -> do
        m <- get
        lStatements .= map (\s -> s{stmtEditing = True}) (modelStatements m)
    DeleteAll ->
        lStatements .= []

modifyStmt
    :: Int
    -> (Statement -> Statement)
    -> Effect () () Model Action
modifyStmt i f = do
    m <- get
    lStatements
        .= [if stmtId s == i then f s else s | s <- modelStatements m]

{- | FileList is array-like, not a JS Array, so 'files' (which
requires Array.isArray) fails. Index by length instead.
-}
chosenFiles :: JSVal -> IO [JSVal]
chosenFiles input = do
    fileList <- input ! ("files" :: MisoString)
    n <- fromJSValUnchecked =<< fileList ! ("length" :: MisoString)
    mapM (fileList !!) [0 :: Int .. n - 1]

-- | Read one chosen file as UTF-8 text and dispatch 'FileLoaded'.
readCsvFile :: Sink Action -> JSVal -> IO ()
readCsvFile sink file = do
    name <- fromJSValUnchecked =<< file ! ("name" :: MisoString)
    reader <- newFileReader
    setField reader ("onload" :: MisoString)
        =<< asyncCallback
            ( do
                result <-
                    fromJSValUnchecked
                        =<< reader ! ("result" :: MisoString)
                sink
                    ( FileLoaded
                        (fromMisoString name)
                        (fromMisoString result)
                    )
            )
    void $ reader # ("readAsText" :: MisoString) $ [file]

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

computeDraft :: Draft -> Either Text (Config, Result)
computeDraft d =
    outcomeOf
        (draftPasted d)
        (draftDateColumn d)
        (draftAmountColumn d)
        (draftFormat d)

analyzeStatement :: Statement -> Outcome
analyzeStatement s =
    case outcomeOf
        (stmtPasted s)
        (stmtDateColumn s)
        (stmtAmountColumn s)
        (stmtFormat s) of
        Left err -> Failure err
        Right (_, result) -> Success result

{- | One paste, one outcome: an error names its cause class and the
result table is not shown for the same submit.
-}
outcomeOf
    :: Text
    -> Maybe Text
    -> Maybe Text
    -> NumberFormat
    -> Either Text (Config, Result)
outcomeOf pasted mDate mAmount fmt
    | T.null (T.strip pasted) =
        Left (renderParseError EmptyInput)
    | otherwise =
        case GP.parseCsv pasted of
            Left e ->
                Left (renderParseError e)
            Right table ->
                case (mDate, mAmount) of
                    (Just dc, Just ac) ->
                        let
                            cfg =
                                Config
                                    { configNumberFormat = fmt
                                    , configDateColumn = dc
                                    , configAmountColumn = ac
                                    }
                        in
                            case GP.extractMovements cfg table of
                                Left e ->
                                    Left (renderParseError e)
                                Right movements ->
                                    Right (cfg, GC.yearResults movements)
                    (Nothing, _) ->
                        Left (renderParseError (MissingColumn "date"))
                    (_, Nothing) ->
                        Left (renderParseError (MissingColumn "amount"))

successfulResults :: [Statement] -> [Result]
successfulResults stmts =
    [ r
    | s <- stmts
    , Success r <- [stmtOutcome s]
    , not (stmtEditing s)
    ]

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
                    [ H.button_
                        [ P.class_
                            ( if modelPage m == StatementsPage
                                then "nav-link active"
                                else "nav-link"
                            )
                        , P.type_ "button"
                        , E.onClick (ShowPage StatementsPage)
                        ]
                        ["Statements"]
                    ]
                , H.li_
                    [P.class_ "nav-item"]
                    [ H.button_
                        [ P.class_
                            ( if modelPage m == AboutPage
                                then "nav-link active"
                                else "nav-link"
                            )
                        , P.type_ "button"
                        , E.onClick (ShowPage AboutPage)
                        ]
                        ["About"]
                    ]
                ]
            ]
        , H.div_
            [P.class_ "container-fluid"]
            [ H.div_
                [P.class_ "main"]
                [ case modelPage m of
                    AboutPage -> aboutView
                    StatementsPage ->
                        H.div_
                            [P.class_ "accordion"]
                            ( [ accordionItem
                                    "report"
                                    (plainTitle "Final report")
                                    ( aggregateView
                                        ( successfulResults
                                            (modelStatements m)
                                        )
                                    )
                              ]
                                <> [ statementItem s
                                   | s <- modelStatements m
                                   ]
                                <> [ accordionItem
                                        "add"
                                        (plainTitle "Add files")
                                        (pasteBody (modelDraft m))
                                   ]
                                <> [ accordionItem
                                    "global"
                                    (plainTitle "Global changes")
                                    globalBody
                                   | not (null (modelStatements m))
                                   ]
                            )
                ]
            , H.div_
                [P.class_ "footer"]
                [footerView]
            ]
        ]

aboutView :: View () Model Action
aboutView =
    H.div_
        [P.class_ "container py-3"]
        [ H.h5_ [] ["About"]
        , H.p_
            []
            [ "This is a simple web application to compute the average deposit and the end of the year balance of a bank account from CSV statements. The average deposit is the daily average of the deposit. The balance is the deposited value at the last day of the year."
            ]
        , H.ul_
            []
            [ H.li_
                []
                [ "Add one or more CSV files (file picker, multiple selection) or paste a CSV. Each statement is configured and reported separately; Final report sums them."
                ]
            , H.li_
                []
                [ "The CSV must have a header with the date and amount fields (names chosen in the form) and should contain the movements of the account history."
                ]
            , H.li_
                []
                ["The date field must be in the format YYYY-MM-DD."]
            , H.li_
                []
                [ "The amount field must be a number, with the decimal separator chosen in the form (European 1.234,56 or American 1,234.56)."
                ]
            ]
        , H.p_
            []
            [ "The result is a table with the average deposit and the balance for each year."
            ]
        , H.p_
            []
            [ "All work stays in this browser tab. Nothing is uploaded to a server."
            ]
        ]

plainTitle :: MisoString -> View () Model Action
plainTitle title =
    H.h5_ [P.class_ "text-center mb-0"] [text title]

-- | One always-open accordion section, matching the production chrome.
accordionItem
    :: MisoString
    -> View () Model Action
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
                [title]
            ]
        , H.div_
            [ P.class_ "accordion-collapse collapse show"
            , P.id_ ident
            ]
            [ H.div_
                [P.class_ "accordion-body d-md-flex w-100 flex-wrap"]
                [body]
            ]
        ]

statementItem :: Statement -> View () Model Action
statementItem s =
    accordionItem
        (ms ("stmt-" <> T.pack (show (stmtId s))))
        (statementHeader s)
        (statementBody s)

statementHeader :: Statement -> View () Model Action
statementHeader s =
    H.div_
        [P.class_ "d-flex align-items-center"]
        [ H.span_
            [P.class_ (ms ("badge " <> badgeClass s <> " ms-2 me-2"))]
            [text (ms (badgeLabel s))]
        , H.h5_ [P.class_ "mb-0"] [text (ms (stmtName s))]
        ]

badgeClass :: Statement -> Text
badgeClass s
    | stmtEditing s = "bg-info"
    | otherwise = case stmtOutcome s of
        Idle -> "bg-warning"
        Failure _ -> "bg-danger"
        Success _ -> "bg-success"

badgeLabel :: Statement -> Text
badgeLabel s
    | stmtEditing s = "Configured"
    | otherwise = case stmtOutcome s of
        Idle -> "Not done"
        Failure _ -> "Failed"
        Success _ -> "Success"

statementBody :: Statement -> View () Model Action
statementBody s
    | stmtEditing s || isIdle (stmtOutcome s) =
        H.div_
            [P.class_ "w-100"]
            [ stmtConfigForm s
            , H.div_
                [P.class_ "d-flex gap-2 mt-3"]
                [ H.button_
                    [ P.class_ "btn btn-primary"
                    , P.type_ "button"
                    , E.onClick (Analyze (stmtId s))
                    ]
                    ["Analyze"]
                , deleteButton (stmtId s)
                ]
            ]
    | otherwise =
        H.div_
            [P.class_ "d-md-flex w-100 flex-wrap gap-3"]
            [ H.div_
                [P.class_ "col-md-4"]
                [configSummary s]
            , H.div_
                [P.class_ "col-md-4"]
                [outcomeView (stmtOutcome s)]
            , H.div_
                [P.class_ "col-md-4"]
                [ H.div_
                    [P.class_ "d-flex gap-2"]
                    [ H.button_
                        [ P.class_ "btn btn-warning"
                        , P.type_ "button"
                        , E.onClick (Reconfigure (stmtId s))
                        ]
                        ["Reconfigure"]
                    , deleteButton (stmtId s)
                    ]
                ]
            ]

isIdle :: Outcome -> Bool
isIdle Idle = True
isIdle _ = False

deleteButton :: Int -> View () Model Action
deleteButton i =
    H.button_
        [ P.class_ "btn btn-danger"
        , P.type_ "button"
        , E.onClick (Delete i)
        ]
        ["Delete"]

stmtConfigForm :: Statement -> View () Model Action
stmtConfigForm s =
    H.div_
        [P.class_ "row g-3"]
        [ H.div_
            [P.class_ "col-md-4"]
            [ columnPicker
                "Date column"
                (StmtDate (stmtId s))
                (stmtDateColumn s)
                (stmtHeaders s)
            ]
        , H.div_
            [P.class_ "col-md-4"]
            [ columnPicker
                "Amount column"
                (StmtAmount (stmtId s))
                (stmtAmountColumn s)
                (stmtHeaders s)
            ]
        , H.div_
            [P.class_ "col-md-4"]
            [ H.label_
                [P.class_ "form-label"]
                ["Number format"]
            , H.select_
                [ P.class_ "form-select"
                , E.onChange
                    ( StmtFormat (stmtId s)
                        . fromMisoString
                    )
                ]
                [ formatOption
                    European
                    "European (1.234,56)"
                    (stmtFormat s)
                , formatOption
                    American
                    "American (1,234.56)"
                    (stmtFormat s)
                ]
            ]
        ]

configSummary :: Statement -> View () Model Action
configSummary s =
    H.div_
        [P.class_ "text-body-secondary"]
        [ H.div_
            []
            [text (ms ("Number format  " <> formatLabel (stmtFormat s)))]
        , H.div_
            []
            [ text
                ( ms
                    ( "Date field name  "
                        <> fromMaybe "" (stmtDateColumn s)
                    )
                )
            ]
        , H.div_
            []
            [ text
                ( ms
                    ( "Amount field name  "
                        <> fromMaybe "" (stmtAmountColumn s)
                    )
                )
            ]
        ]

formatLabel :: NumberFormat -> Text
formatLabel European = "European"
formatLabel American = "American"

pasteBody :: Draft -> View () Model Action
pasteBody d =
    H.div_
        [P.class_ "w-100"]
        [ H.p_
            [P.class_ "hint text-body-secondary"]
            [ "Choose one or more CSV files, or paste a CSV and submit. Each statement is configured and reported separately; Final report sums them."
            ]
        , H.div_
            [P.class_ "mb-3"]
            [ H.label_
                [P.class_ "form-label"]
                ["CSV file:"]
            , H.input_
                [ P.id_ "csv-data"
                , P.class_ "csv-file form-control"
                , P.type_ "file"
                , P.multiple_ True
                , P.accept_ ".csv,text/csv,text/plain"
                , E.onChangeWith (const FilesChosen)
                ]
            ]
        , H.div_
            [P.class_ "mb-3"]
            [ H.label_
                [P.class_ "form-label"]
                ["Or paste CSV"]
            , H.textarea_
                [ P.class_ "paste form-control font-monospace"
                , P.rows_ "10"
                , P.placeholder_
                    "date,amount\n2023-01-01,100"
                , P.value_ (ms (draftPasted d))
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
                    (draftDateColumn d)
                    (draftHeaders d)
                ]
            , H.div_
                [P.class_ "col-md-4"]
                [ columnPicker
                    "Amount column"
                    AmountColumnChanged
                    (draftAmountColumn d)
                    (draftHeaders d)
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
                        (draftFormat d)
                    , formatOption
                        American
                        "American (1,234.56)"
                        (draftFormat d)
                    ]
                ]
            ]
        , maybe
            (H.span_ [] [])
            ( \err ->
                H.div_
                    [P.class_ "error alert alert-danger"]
                    [ H.h5_ [] ["Error in the request"]
                    , H.p_ [P.class_ "mb-0"] [text (ms err)]
                    ]
            )
            (draftError d)
        , H.button_
            [ P.class_ "compute btn btn-primary"
            , P.type_ "button"
            , E.onClick ComputeRequested
            ]
            ["Submit"]
        ]

globalBody :: View () Model Action
globalBody =
    H.div_
        [P.class_ "d-grid gap-2 d-md-flex justify-content-md-end w-100"]
        [ H.button_
            [ P.class_ "btn btn-warning"
            , P.type_ "button"
            , E.onClick ReconfigureAll
            ]
            ["Reconfigure all files"]
        , H.button_
            [ P.class_ "btn btn-danger"
            , P.type_ "button"
            , E.onClick DeleteAll
            ]
            ["Delete all files"]
        ]

aggregateView :: [Result] -> View () Model Action
aggregateView rs = outcomeView (aggregateOutcome rs)

aggregateOutcome :: [Result] -> Outcome
aggregateOutcome [] = Idle
aggregateOutcome rs = Success (GC.sumResults rs)

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

-- | Error node or result table (year, average, last balance).
outcomeView :: Outcome -> View () Model Action
outcomeView = \case
    Idle ->
        H.p_
            [P.class_ "idle text-body-secondary"]
            ["No results."]
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
