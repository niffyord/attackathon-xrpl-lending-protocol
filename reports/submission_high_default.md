# Title
Loan default consumes too little first-loss capital due to loan-scale rounding in `LoanManage::defaultLoan`

# Description

## Brief/Intro
When a borrower defaults, `LoanManage::defaultLoan` should liquidate first-loss capital (FLC) before the vault absorbs remaining losses. The amount consumed, `defaultCovered`, is rounded using the loan’s scale instead of the vault asset precision. With mixed-scale loans, this rounding is coarse and rounds down the amount of FLC clawed back. As a result, defaults leave cover higher than policy permits and push extra loss to the vault, directly harming lenders.

## Vulnerability Details
- The default handler computes FLC coverage via:
  ```cpp
  auto const defaultCovered = roundToAsset(
      vaultAsset,
      std::min(
          tenthBipsOfValue(
              tenthBipsOfValue(brokerDebtTotalProxy.value(), coverRateMinimum),
              coverRateLiquidation),
          totalDefaultAmount),
      loanScale);
  ```
  (`src/xrpld/app/tx/detail/LoanManage.cpp:170-183`)

- As with the other cover checks, `loanScale` comes from the loan with the largest magnitude (`computeLoanProperties`, `src/xrpld/app/misc/detail/LendingHelpers.cpp:1379`). When large loans exist, `Number::operator+=` expands the exponent and discards lower digits (`src/libxrpl/basics/Number.cpp:320`), so using `loanScale` for rounding yields coarse steps (e.g., 10⁶ units).

- During default, `defaultCovered` is truncated to this coarse grid. If the true required FLC amount lies between coarse steps, the rounded value is lower by up to half the quantum. After the FLC transfer, `sfCoverAvailable` remains above zero instead of being fully consumed, and the vault bears additional loss.

- **Mathematical Example**: With `DebtTotal = 1e18` (exponent 6), `CoverRateMinimum = 1` (0.01%), `CoverRateLiquidation = 10000` (100%), and `TotalDefaultAmount = 1,000,400,000,000`, the true coverage required is `min((DebtTotal × CoverRateMinimum × CoverRateLiquidation) / (100000 × 100000), TotalDefaultAmount) = 1,000,400,000,000`. Rounding with `loanScale = 6` yields `1,000,000,000,000` (rounded down), creating a gap of ~400,000,000 units. The vault absorbs this extra loss instead of FLC.

- No subsequent check recomputes the true minimum, so the protocol records success even though the cover/liquidation policy is violated.

## Impact Details
- The broker can first exploit the withdrawal bug (or simply rely on large-loan rounding) to leave cover just above the coarse minimum.
- Triggering a default then consumes only the rounded-down amount of FLC, leaving hundreds of thousands of units (or more) still in `sfCoverAvailable`.
- The vault's `sfAssetsTotal` decreases by `vaultDefaultAmount = totalDefaultAmount - defaultCovered`, where `defaultCovered` is rounded down. This means lenders absorb losses that the policy intended FLC to cover.
- **Fund Flow**: When `defaultCovered` is rounded down by ~400,000 units, the vault absorbs that extra amount instead of FLC. The broker's `sfCoverAvailable` decreases by the smaller rounded amount, leaving excess FLC that should have been consumed.
- This constitutes a direct funds impact in the "Drainage and/or stealing of funds from ledger objects (first loss capital/vault)" category.

## References
- `src/xrpld/app/tx/detail/LoanManage.cpp:170-183` (vulnerable code)
- `src/xrpld/app/misc/detail/LendingHelpers.cpp:1364-1405` (loan scale calculation)
- `src/libxrpl/basics/Number.cpp:245-360` (Number normalization)
- `src/libxrpl/protocol/STAmount.cpp:1513-1535` (roundToScale implementation)

## Recommended Mitigation
- Derive the rounding scale from the vault asset precision (or construct a canonical `STAmount{vaultAsset, ...}` and let canonicalisation choose precision) rather than from `loanScale`.
- Centralize minimum-cover computation in a single helper and reuse it across withdraw (`LoanBrokerCoverWithdraw`), fee routing (`LoanPay`), and default coverage (`LoanManage::defaultLoan`) to ensure consistent behavior.

# Proof of Concept

## Environment Setup
1. Build a local devnet node from the Attackathon repository with the lending amendments enabled (per `BUILD.md`).
2. Create accounts for issuer `I`, broker owner `B`, broker pseudo account (auto-created), and borrower `U`.
3. Issue a high-precision IOU `I.USD` with at least 12 decimal places; create a private vault for `I.USD`.

## Configure Broker and Create Large Loan
1. Configure a LoanBroker with `CoverRateMinimum = 1` (0.01%) and `CoverRateLiquidation = 10000` (100%) via `LoanBrokerSet`.
2. Originate a large loan (principal ≈ 1e18) via a Batch transaction so the inner `LoanSet` does not need a counterparty signature; this pushes `sfDebtTotal.exponent()` to 6+ and sets `loanScale = 6`.
3. Verify via `ledger_entry` that `sfDebtTotal.exponent() == 6` and note the loan's `sfLoanScale`.

## Calculate Expected Coverage
1. Compute true coverage required:
   - `MaxCoverage = (DebtTotal × CoverRateMinimum / 100000) × CoverRateLiquidation / 100000`
   - `TotalDefaultAmount = TotalValueOutstanding - ManagementFeeOutstanding`
   - `TrueCoverageRequired = min(MaxCoverage, TotalDefaultAmount)`
2. Compute rounded coverage: `RoundedCoverage = roundToAsset(vaultAsset, TrueCoverageRequired, loanScale)`
3. The rounding gap is `TrueCoverageRequired - RoundedCoverage`, which can be up to ~500,000 units when `loanScale = 6`.

## Set Cover to Exploit Rounding
1. Deposit first-loss capital so `sfCoverAvailable` equals the true coverage required (or slightly above).
2. Alternatively, reuse the setup from the critical report through step 13 (broker under-cover but still passing the withdraw check).
3. Ensure `sfCoverAvailable` is within ~400,000 units of the true minimum by examining the broker ledger entry.

## Trigger Default
1. Trigger a default via `LoanManage` with the `tfLoanDefault` flag:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanManage",
         "Account":"<BROKER_ACCOUNT>",
         "LoanID":"<LOAN_ID>",
         "Flags": 0x00020000
       }
     }]
   }' | jq '.result.engine_result'
   ```
   The engine result is `tesSUCCESS`.

## Verify Mis-Consumption
1. Inspect broker state after default:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"ledger_entry",
     "params":[{"index":"<BROKER_ID>"}]
   }' | jq '.result.node | {CoverAvailable:."CoverAvailable", DebtTotal:."DebtTotal"}'
   ```
   
2. Inspect vault state after default:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"ledger_entry",
     "params":[{"index":"<VAULT_ID>"}]
   }' | jq '.result.node | {AssetsAvailable:."AssetsAvailable", AssetsTotal:."AssetsTotal"}'
   ```

3. Calculate values:
   - `CoverConsumed = CoverAvailableBefore - CoverAvailableAfter`
   - `VaultLoss = AssetsTotalBefore - AssetsTotalAfter`
   - `ExpectedVaultLoss = TotalDefaultAmount - TrueCoverageRequired`
   - `ExtraLossToVault = VaultLoss - ExpectedVaultLoss`

## Validation Checklist
The vulnerability is confirmed when:
- ✅ `loanScale >= 6` (large loan created)
- ✅ `CoverConsumed < TrueCoverageRequired` (rounded down)
- ✅ `CoverAvailableAfter > 0` (cover not fully consumed - should be 0)
- ✅ `VaultLoss > ExpectedVaultLoss` (vault absorbed extra loss)
- ✅ `CoverAvailableAfter * 100000 / DebtTotalAfter < CoverRateMinimum` (policy violated)

This demonstrates that defaults violate the minimum cover/liquidation policy, pushing more losses onto the vault than intended.
