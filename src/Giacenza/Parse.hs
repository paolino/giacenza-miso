{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Giacenza.Parse
Description : CSV text to headers, rows and movements
Copyright   : (c) 2026, paolino
License     : BSD-3-Clause

Owns CSV parsing: text to headers and rows (giacenza-browser
splitter), header-name lookup, date fields, and amount fields under a
'NumberFormat' with production @parseValue@ semantics. Does not own
daily expansion or year aggregation.
-}
module Giacenza.Parse
    ( CsvTable (..)
    , parseCsv
    , parseDate
    , parseAmount
    , extractMovements
    ) where

import Data.Char (isDigit)
import Data.List (elemIndex, foldl')
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Giacenza.Types

{- | Parsed CSV: ordered header names and ordered field rows.
Duplicate header names: first match wins. Empty input is not a
table; header-only is a table with no rows.
-}
data CsvTable = CsvTable
    { headers :: [Text]
    , rows :: [[Text]]
    }
    deriving (Show, Eq)

{- | First non-empty line is the header, the rest are data rows.
A paste without any non-empty line is 'EmptyInput'.
-}
parseCsv :: Text -> Either ParseError CsvTable
parseCsv csvText =
    case nonEmptyLines csvText of
        [] -> Left EmptyInput
        (headerLine : dataLines) ->
            Right
                CsvTable
                    { headers = splitCsvLine headerLine
                    , rows = map splitCsvLine dataLines
                    }

-- | @YYYY-MM-DD@ calendar dates only.
parseDate :: Text -> Either ParseError Day
parseDate raw =
    maybe (Left (InvalidDate raw)) Right parsed
  where
    parsed =
        parseTimeM
            False
            defaultTimeLocale
            "%Y-%m-%d"
            (T.unpack (T.strip raw))
            :: Maybe Day

{- | Production parseValue: optional leading @-@; integer groups
joined by the thousands separator, each folded @w*1000 + t@;
optional decimal separator then an integer @c@ contributing
@c/100@ (so European @1,5@ = 1.05). Space-stripped groups are
allowed.
-}
parseAmount :: NumberFormat -> Text -> Either ParseError Value
parseAmount fmt raw =
    maybe (Left (InvalidAmount raw)) (Right . Value) amount
  where
    (decSep, thouSep) = numberFormatSeparators fmt
    body = T.unpack (T.strip raw)
    amount = case body of
        ('-' : rest) -> amountFrom negate rest
        _ -> amountFrom id body
    amountFrom sign s =
        case breakFirst decSep s of
            Nothing -> Nothing
            Just (intPart, mDec) -> do
                whole <- foldGroups thouSep intPart
                cents <- maybe (pure 0) decCents mDec
                pure (sign (fromIntegral whole + fromIntegral cents / 100))

{- | Movements in CSV row order from the configured columns. Fails on
a missing date or amount column, on any bad date, on any bad
amount, and on any row shorter than the header.
-}
extractMovements :: Config -> CsvTable -> Either ParseError [Movement]
extractMovements cfg table = do
    dateIdx <- columnIndex (configDateColumn cfg) (headers table)
    amountIdx <- columnIndex (configAmountColumn cfg) (headers table)
    traverse (rowMovement dateIdx amountIdx) (rows table)
  where
    columnIndex name hs =
        maybe (Left (MissingColumn name)) Right (elemIndex name hs)
    rowMovement dateIdx amountIdx row =
        case (fieldAt dateIdx row, fieldAt amountIdx row) of
            (Just dateField, Just amountField) -> do
                day <- parseDate dateField
                value <- parseAmount (configNumberFormat cfg) amountField
                pure (Movement day value)
            _ -> Left ShortRow
    fieldAt i xs = case drop i xs of
        (x : _) -> Just x
        [] -> Nothing

-- | Normalize CR/LF endings, drop lines empty after trim.
nonEmptyLines :: Text -> [Text]
nonEmptyLines =
    filter (not . T.null . T.strip)
        . T.splitOn "\n"
        . normalizeEndings

normalizeEndings :: Text -> Text
normalizeEndings = T.replace "\r\n" "\n" . T.replace "\r" "\n"

{- | giacenza-browser splitter: quotes toggle; comma and semicolon
outside quotes separate fields; every field is trimmed.
-}
splitCsvLine :: Text -> [Text]
splitCsvLine line = map T.strip (reverse (go (T.unpack line) [] "" False))
  where
    go [] fields field _ = field : fields
    go ('"' : rest) fields field inQuotes =
        go rest fields field (not inQuotes)
    go (c : rest) fields field inQuotes
        | (c == ',' || c == ';') && not inQuotes =
            go rest (field : fields) "" False
        | otherwise =
            go rest fields (T.snoc field c) inQuotes

-- | Split at the first occurrence of the decimal separator.
breakFirst :: Char -> String -> Maybe (String, Maybe String)
breakFirst sep s = case break (== sep) s of
    (intPart, []) -> Just (intPart, Nothing)
    (intPart, _ : decRest) -> Just (intPart, Just decRest)

-- | Fold thousands-separated digit groups: @w*1000 + t@.
foldGroups :: Char -> String -> Maybe Integer
foldGroups thouSep s = do
    groups <- traverse digitGroup (splitOnChar thouSep s)
    pure (foldl' (\w g -> w * 1000 + g) 0 groups)

-- | Decimal digits only, spaces stripped, at least one digit.
digitGroup :: String -> Maybe Integer
digitGroup str =
    let cleaned = filter (/= ' ') str
    in  if not (null cleaned) && all isDigit cleaned
            then Just (read cleaned)
            else Nothing

{- | The fractional part after the decimal separator: digits only,
contributing @c/100@ (not @c/10^n@).
-}
decCents :: String -> Maybe Integer
decCents = digitGroup

splitOnChar :: Char -> String -> [String]
splitOnChar c s = case break (== c) s of
    (a, []) -> [a]
    (a, _ : rest) -> a : splitOnChar c rest
