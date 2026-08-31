{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Giacenza.ComputeSpec
Description : Proofs of the compute invariants (spec issue #1)
Copyright   : (c) 2026, paolino
License     : BSD-3-Clause

Each proof named prop_inv1_* pins one BLOCKING invariant from the
spec debrief, at the pipeline level (parseCsv + extractMovements +
yearResults), so the proof crosses the parse/compute seam.
-}
module Giacenza.ComputeSpec (spec) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar
import Giacenza.Compute (sumResults, yearResults)
import Giacenza.Parse (extractMovements, parseCsv)
import Giacenza.Types
import Test.Hspec
import Test.QuickCheck qualified as QC

-- | Run the full paste pipeline with the given config.
runPipelineWith :: Config -> Text -> Either ParseError Result
runPipelineWith cfg csvText = do
    table <- parseCsv csvText
    movements <- extractMovements cfg table
    pure (yearResults movements)

-- | Pipeline with the canonical @date@ / @amount@ American config.
american :: Text -> Either ParseError Result
american = runPipelineWith (Config American "date" "amount")

{- | Pipeline with a European @date@ / @amount@ config. European is
the UI default (FR-003), so this is the seam the product ships on.
-}
euro :: Text -> Either ParseError Result
euro = runPipelineWith (Config European "date" "amount")

{- | Within a relative 1e-6 of the expected Double (summed daily
balances lose ULPs that exact 'shouldBe' cannot forgive).
-}
near :: Double -> Value -> Bool
near expected (Value actual) =
    abs (actual - expected) <= 1e-6 * max 1 (abs expected)

{- | Assert a pipeline row through to saldo and giacenza: saldo is a
directly emitted value (exact), giacenza is a summed average
(approximate).
-}
rowNear :: Integer -> Double -> Result -> Expectation
rowNear y expected result =
    case yearRow result y of
        Just (Saldo s, Giacenza g) -> do
            s `shouldBe` Value expected
            g `shouldSatisfy` near expected
        Nothing ->
            expectationFailure (show y <> " row missing from result")

-- | Look up one year row of a result.
yearRow :: Result -> Integer -> Maybe YearResult
yearRow (Result mp) y = Map.lookup (Year y) mp

-- | One @date,amount@ line for a whole-integer amount.
csvLine :: Day -> Integer -> Text
csvLine d n =
    "date,amount\n"
        <> T.pack (showGregorian d)
        <> ","
        <> T.pack (show n)

-- | Any day of 2023.
genDay2023 :: QC.Gen Day
genDay2023 = do
    n <- QC.chooseInteger (1, 365)
    pure (addDays (fromIntegral (n - 1)) (fromGregorian 2023 1 1))

-- | Whole-integer amounts keep every daily sum exact in Double.
genWholeAmount :: QC.Gen Integer
genWholeAmount = QC.chooseInteger (-1000000, 1000000)

spec :: Spec
spec = do
    describe "sumResults" $ do
        it "adds saldo and giacenza per year across statements" $ do
            let
                one =
                    either
                        (error "const csv")
                        id
                        (american "date,amount\n2023-01-01,100")
            case yearRow (sumResults [one, one]) 2023 of
                Just (Saldo s, Giacenza g) -> do
                    s `shouldBe` Value 200
                    g `shouldSatisfy` near 200
                Nothing ->
                    expectationFailure "2023 missing from sum"

    describe "pipeline (parseCsv + extractMovements + yearResults)" $ do
        it
            "prop_inv1_euro: European config carries 1.234,56 through to saldo/giacenza"
            $ do
                -- configNumberFormat must reach parseAmount through the
                -- whole pipeline: 1.234,56 is 1234.56 under European and
                -- rejected under American; asserted through to the row.
                either
                    (const $ expectationFailure "euro paste must parse")
                    (rowNear 2023 (1234 + 56 / 100))
                    (euro "date;amount\n2023-01-01;\"1.234,56\"")
                either
                    (const $ expectationFailure "negated euro paste must parse")
                    (rowNear 2023 (negate (1234 + 56 / 100)))
                    (euro "date;amount\n2023-01-01;\"-1.234,56\"")
                -- ... and the misformatted literal is a visible error.
                american "date;amount\n2023-01-01;\"1.234,56\""
                    `shouldBe` Left (InvalidAmount "1.234,56")

        it
            "prop_inv1_amer: American config carries 1,234.56 through to saldo/giacenza"
            $ do
                -- Same seam from the American side: 1,234.56 is 1234.56
                -- under American and rejected under European.
                either
                    (const $ expectationFailure "amer paste must parse")
                    (rowNear 2023 (1234 + 56 / 100))
                    (american "date;amount\n2023-01-01;\"1,234.56\"")
                -- ... and the misformatted literal is a visible error.
                euro "date;amount\n2023-01-01;\"1,234.56\""
                    `shouldBe` Left (InvalidAmount "1,234.56")

    describe "yearResults" $ do
        it
            "prop_inv1_const: American date,amount 2023-01-01,100 -> saldo 100 giacenza 100"
            $ american "date,amount\n2023-01-01,100"
                `shouldBe` Right
                    ( Result
                        ( Map.singleton
                            (Year 2023)
                            (Saldo (Value 100), Giacenza (Value 100))
                        )
                    )

        it
            "prop_inv1_const: any single 2023 movement gives saldo == amount, giacenza over its emitted fill"
            $ QC.property
            $ QC.forAll genDay2023
            $ \d ->
                QC.forAll genWholeAmount $ \n ->
                    let fill = diffDays (fromGregorian 2023 12 31) d + 1
                    in  case american (csvLine d n) of
                            Right result ->
                                case yearRow result 2023 of
                                    Just (Saldo s, Giacenza g) ->
                                        QC.conjoin
                                            [ s QC.=== Value (fromIntegral n)
                                            , g QC.=== Value (fromIntegral n * fromIntegral fill / 365)
                                            ]
                                    Nothing ->
                                        QC.counterexample
                                            "2023 row missing"
                                            False
                            Left e ->
                                QC.counterexample ("unexpected error: " <> show e) False

        it "prop_inv1_gap: 2024 leap, sparse movements carry, fill to 31 Dec" $
            american "date,amount\n2024-01-01,1000\n2024-06-01,-200"
                `shouldBe` Right
                    ( Result
                        ( Map.singleton
                            (Year 2024)
                            ( Saldo (Value 800)
                            , Giacenza (Value ((152 * 1000 + 214 * 800) / 366))
                            )
                        )
                    )

        it
            "prop_inv1_partial_year: days before the first movement are omitted"
            $ american "date,amount\n2023-06-01,50"
                `shouldBe` Right
                    ( Result
                        ( Map.singleton
                            (Year 2023)
                            (Saldo (Value 50), Giacenza (Value (214 * 50 / 365)))
                        )
                    )

        it "prop_inv1_year_cross: 31 Dec then 1 Jan give two correct years" $
            american "date,amount\n2023-12-31,10\n2024-01-01,5"
                `shouldBe` Right
                    ( Result
                        ( Map.fromList
                            [
                                ( Year 2023
                                , (Saldo (Value 10), Giacenza (Value (10 / 365)))
                                )
                            , (Year 2024, (Saldo (Value 15), Giacenza (Value 15)))
                            ]
                        )
                    )

        it
            "prop_inv1_empty_rows: header-only CSV yields an empty result, not an error"
            $ do
                american "date,amount"
                    `shouldBe` Right (Result Map.empty)
                american "date,amount\n"
                    `shouldBe` Right (Result Map.empty)
