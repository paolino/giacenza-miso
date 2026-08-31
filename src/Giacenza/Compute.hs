{- |
Module      : Giacenza.Compute
Description : Movements to per-year saldo and giacenza
Copyright   : (c) 2026, paolino
License     : BSD-3-Clause

Owns the production compute semantics: movements (already in apply
order) expand to a dense daily balance via 'foldDays' — gaps carry
the running balance, days before the first movement are omitted,
after the last movement the balance fills through 31 Dec of that
movement's year — and each year with a 31 Dec emitted balance gets
its saldo and a leap-aware giacenza divided by the calendar year
length. Does not own CSV or DOM.
-}
module Giacenza.Compute
    ( yearResults
    ) where

import Data.Function (on)
import Data.List (groupBy)
import Data.Map.Merge.Strict qualified as MapMerge
import Data.Map.Strict qualified as Map
import Data.Time.Calendar
    ( Day
    , fromGregorian
    , isLeapYear
    , toGregorian
    )
import Giacenza.Types

{- | Per-year saldo (31 Dec emitted balance) and giacenza (sum of
emitted daily balances divided by 365, or 366 if leap). Years
without a 31 Dec emitted balance are absent, not zero.
-}
yearResults :: [Movement] -> Result
yearResults movements =
    Result
        ( MapMerge.merge
            MapMerge.dropMissing
            MapMerge.dropMissing
            (MapMerge.zipWithMatched (\_ saldo giac -> (saldo, giac)))
            saldos
            giacenzas
        )
  where
    days = foldDays movements

    saldos =
        Map.fromList
            [ (Year y, Saldo v)
            | (d, v) <- days
            , isYearEnd d
            , let (y, _, _) = toGregorian d
            ]

    giacenzas =
        Map.fromList
            [ ( Year y
              , Giacenza
                    (Value (unValue (sumValues vs) / fromIntegral (yearLength y)))
              )
            | grp@((d0, _) : _) <- groupBy ((==) `on` (yearOf . fst)) days
            , let y = yearOf d0
            , let vs = map snd grp
            ]

{- | Expand sparse movements to a dense daily balance, in apply
order: days before the first movement are omitted; each subsequent
movement emits the previous balance up to the day before it; after
the last movement the final balance fills through 31 Dec of that
movement's year.
-}
foldDays :: [Movement] -> [(Day, Value)]
foldDays = go Nothing
  where
    go Nothing [] = []
    go Nothing (Movement day amount : rest) =
        go (Just (day, amount)) rest
    go (Just (day', value)) [] =
        [(d, value) | d <- [day' .. lastDayOfYear day']]
    go (Just (day', value)) (Movement day amount : rest) =
        [(d, value) | d <- [day' .. pred day]]
            ++ go (Just (day, value + amount)) rest

-- | Calendar year length as the giacenza divisor.
yearLength :: Integer -> Int
yearLength y = if isLeapYear y then 366 else 365

-- | 31 December of a day's year.
lastDayOfYear :: Day -> Day
lastDayOfYear d = fromGregorian (yearOf d) 12 31

-- | Is the day 31 December?
isYearEnd :: Day -> Bool
isYearEnd d = case toGregorian d of
    (_, 12, 31) -> True
    _ -> False

-- | Calendar year of a day.
yearOf :: Day -> Integer
yearOf d = y
  where
    (y, _, _) = toGregorian d

-- | Sum daily balances.
sumValues :: [Value] -> Value
sumValues = sum
