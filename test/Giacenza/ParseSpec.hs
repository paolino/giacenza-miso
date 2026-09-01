{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Giacenza.ParseSpec
Description : Proofs of the parse invariants (spec issue #1)
Copyright   : (c) 2026, paolino
License     : BSD-3-Clause

Each proof named prop_inv1_* pins one BLOCKING invariant from the
spec debrief. Assertions match exact error constructors so a stub or
a silent-skip mutant cannot pass.
-}
module Giacenza.ParseSpec (spec) where

import Data.Text qualified as T
import Data.Time.Calendar (fromGregorian)
import Giacenza.Parse
import Giacenza.Types
import Test.Hspec

-- | Run extractMovements over a paste with the given config.
extract :: Config -> T.Text -> Either ParseError [Movement]
extract cfg csvText = extractMovements cfg =<< parseCsv csvText

-- | Canonical American @date@ / @amount@ pipeline.
american :: T.Text -> Either ParseError [Movement]
american = extract (Config American "date" "amount")

spec :: Spec
spec = do
    describe "parseAmount" $ do
        -- The prop_inv1_euro / prop_inv1_amer proofs live at the
        -- pipeline layer in Giacenza.ComputeSpec (the spec states
        -- these invariants on saldo/giacenza); this keeps the
        -- direct parseAmount edges pinned.
        it "pins the European/American acceptance edges directly" $ do
            parseAmount European "1.234,56"
                `shouldBe` Right (Value (1234 + 56 / 100))
            parseAmount European "1,5"
                `shouldBe` Right (Value (1 + 5 / 100))
            parseAmount American "1,234.56"
                `shouldBe` Right (Value (1234 + 56 / 100))
            parseAmount American "100"
                `shouldBe` Right (Value 100)

        it "rejects malformed amounts as InvalidAmount" $ do
            parseAmount European "12a" `shouldBe` Left (InvalidAmount "12a")
            parseAmount European "1..2" `shouldBe` Left (InvalidAmount "1..2")
            parseAmount European "-" `shouldBe` Left (InvalidAmount "-")
            parseAmount European "1,234,56"
                `shouldBe` Left (InvalidAmount "1,234,56")

    describe "parseCsv" $ do
        it "prop_inv1_error_empty: empty paste is a visible error" $ do
            parseCsv "" `shouldBe` Left EmptyInput
            parseCsv "   \n\t " `shouldBe` Left EmptyInput

        it "splits on comma or semicolon and trims fields" $
            parseCsv " date ; \"amount, eur\" \n 2023-01-01 ; 100 "
                `shouldBe` Right
                    ( CsvTable
                        { headers = ["date", "amount, eur"]
                        , rows = [["2023-01-01", "100"]]
                        }
                    )

        it "keeps comma and semicolon inside quotes as data" $
            parseCsv "a,b\n\"x,;y\",z"
                `shouldBe` Right
                    (CsvTable{headers = ["a", "b"], rows = [["x,;y", "z"]]})

    describe "extractMovements" $ do
        it
            "prop_inv1_error_date: bad date and missing column are errors, no numbers"
            $ do
                american "date,amount\n2023-01-01,100\n2023-13-40,5"
                    `shouldBe` Left (InvalidDate "2023-13-40")
                american "date,amount\nnot-a-date,5"
                    `shouldBe` Left (InvalidDate "not-a-date")
                extract
                    (Config American "datum" "amount")
                    "date,amount\n2023-01-01,100"
                    `shouldBe` Left (MissingColumn "datum")
                extract
                    (Config American "date" "euro")
                    "date,amount\n2023-01-01,100"
                    `shouldBe` Left (MissingColumn "euro")

        it "prop_inv1_error_empty: empty paste extracts nothing and errors" $ do
            american "" `shouldBe` Left EmptyInput

        it "reads movements in CSV row order from the configured columns" $
            american "date,amount\n2023-01-01,100\n2024-06-01,-200"
                `shouldBe` Right
                    [ Movement (fromGregorian 2023 1 1) (Value 100)
                    , Movement (fromGregorian 2024 6 1) (Value (-200))
                    ]

        it "flags a row shorter than the header as ShortRow" $
            american "date,amount\n2023-01-01"
                `shouldBe` Left ShortRow
