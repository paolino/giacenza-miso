{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Giacenza.Types
Description : Shared language of the giacenza calculator
Copyright   : (c) 2026, paolino
License     : BSD-3-Clause

Money, date, movement and result vocabulary shared by the parser, the
compute core and the miso UI. Do not fork a second money or date
vocabulary in the UI.
-}
module Giacenza.Types
    ( Value (..)
    , Year (..)
    , Saldo (..)
    , Giacenza (..)
    , Movement (..)
    , NumberFormat (..)
    , numberFormatSeparators
    , Config (..)
    , YearResult
    , Result (..)
    , ParseError (..)
    , renderParseError
    ) where

import Data.Map.Strict (Map)
import Data.Text (Text)
import Data.Time.Calendar (Day)

{- | Monetary amount. Signed. Internal representation is fractional
(production uses 'Double'); display is two decimal places.
-}
newtype Value = Value {unValue :: Double}
    deriving newtype (Show, Eq, Ord, Num, Fractional)

-- | Gregorian calendar year.
newtype Year = Year {unYear :: Integer}
    deriving newtype (Show, Eq, Ord, Num)

-- | Balance emitted on 31 December of a year.
newtype Saldo = Saldo {unSaldo :: Value}
    deriving newtype (Show, Eq, Num, Fractional)

-- | Average daily balance of a year.
newtype Giacenza = Giacenza {unGiacenza :: Value}
    deriving newtype (Show, Eq, Num, Fractional)

{- | A single bank movement: an amount delta applied on a date (not a
running balance). CSV row order is the apply order.
-}
data Movement = Movement
    { date :: Day
    , amount :: Value
    }
    deriving (Show, Eq)

-- | Number format for parsing amounts.
data NumberFormat
    = -- | @1.234,56@ — decimal @,@, thousands @.@
      European
    | -- | @1,234.56@ — decimal @.@, thousands @,@
      American
    deriving (Show, Eq, Enum, Bounded)

-- | @(decimal separator, thousands separator)@ of a 'NumberFormat'.
numberFormatSeparators :: NumberFormat -> (Char, Char)
numberFormatSeparators European = (',', '.')
numberFormatSeparators American = ('.', ',')

{- | UI configuration: which header names hold the date and the
amount, and how amounts are written. Names match exactly after trim.
-}
data Config = Config
    { configNumberFormat :: NumberFormat
    , configDateColumn :: Text
    , configAmountColumn :: Text
    }
    deriving (Show, Eq)

-- | Per-year outcome: end-of-year balance and average daily balance.
type YearResult = (Saldo, Giacenza)

{- | Map from year to 'YearResult' for years that have a 31 Dec
emitted balance. Missing years are absent, not zero.
-}
newtype Result = Result {unResult :: Map Year YearResult}
    deriving newtype (Show, Eq)

-- | Why a paste could not be turned into movements or a result.
data ParseError
    = -- | The paste has no content at all.
      EmptyInput
    | -- | A configured column name is not in the header.
      MissingColumn Text
    | -- | A date field is not a @YYYY-MM-DD@ calendar date.
      InvalidDate Text
    | -- | An amount field does not parse under the configured format.
      InvalidAmount Text
    | -- | A row has fewer fields than the header.
      ShortRow
    deriving (Show, Eq)

-- | Human-readable error, naming the cause class.
renderParseError :: ParseError -> Text
renderParseError = \case
    EmptyInput ->
        "Empty input: paste a CSV with a header row"
    MissingColumn name ->
        "Column not found in header: \"" <> name <> "\""
    InvalidDate raw ->
        "Invalid date (expected YYYY-MM-DD): \"" <> raw <> "\""
    InvalidAmount raw ->
        "Invalid amount: \"" <> raw <> "\""
    ShortRow ->
        "Row has fewer fields than the header"
