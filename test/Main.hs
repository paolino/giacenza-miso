{- |
Module      : Main
Description : Test runner for the giacenza invariant proofs
Copyright   : (c) 2026, paolino
License     : BSD-3-Clause
-}
module Main (main) where

import Giacenza.ComputeSpec qualified (spec)
import Giacenza.ParseSpec qualified (spec)
import Test.Hspec (hspec)

main :: IO ()
main = hspec $ do
    Giacenza.ComputeSpec.spec
    Giacenza.ParseSpec.spec
