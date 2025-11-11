# Title
Rounding error in LoanPay fee routing lets broker siphon first-loss capital below minimum cover

# Description

## Brief/Intro
`LoanPay::doApply` decides whether broker fees reinforce first-loss cover or go straight to the broker owner. The minimum-cover check it uses is rounded with the current loan’s scale instead of the vault asset precision, so it rounds down whenever the debt total’s exponent is coarse. A broker who keeps cover inside that rounding slack can continue receiving fees even though real cover is below the mandated floor, draining first-loss capital from the vault.

## Vulnerability Details
- In `LoanPay::doApply`, the predicate is:
  ```cpp
  bool const sendBrokerFeeToOwner = coverAvailableProxy >=
          roundToAsset(asset,
                       tenthBipsOfValue(
                           debtTotalProxy.value(), coverRateMinimum),
                       loanScale) &&
      !isDeepFrozen(view, brokerOwner, asset);
  ```
  (`src/xrpld/app/tx/detail/LoanPay.cpp:270-274`)
- `loanScale` reflects the biggest outstanding loan's exponent (`computeLoanProperties`, `src/xrpld/app/misc/detail/LendingHelpers.cpp:1379`). `Number::operator+=` moves digits into that exponent when debts are large (`src/libxrpl/basics/Number.cpp:320`), so `roundToAsset` ends up rounding at very coarse increments (`src/libxrpl/protocol/STAmount.cpp:1513-1535`).
- When real cover is slightly below the true `CoverRateMinimum × DebtTotal` but above the rounded floor, fees keep going to the owner instead of replenishing cover.
- **Mathematical Example**: With `DebtTotal = 1e18` (exponent 6), `CoverRateMinimum = 1` (0.01%), the true minimum cover is `1e18 × 1 / 100000 = 1e13`. If the true minimum is `10,000,400,000` units, rounding with `loanScale = 6` yields `10,000,000,000` (rounded down), creating a gap of ~400,000 units. When `CoverAvailable = 10,000,200,000` (below true minimum but above rounded), the check passes and fees route to owner.

## Impact Details
- Borrower payments keep crediting fees to the owner while first-loss cover remains insufficient.
- Vault participants lose funds they expect to be protected by the cover ratio, fitting the "Drainage and/or stealing of funds from ledger objects (vault, first loss capital)" impact.
- Repeated payments can drain hundreds of thousands of units from the FLC pool, accelerating cover erosion and compounding shortfalls.

## References
- `src/xrpld/app/tx/detail/LoanPay.cpp:270-274` (vulnerable code)
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
1. Configure a LoanBroker with `CoverRateMinimum = 1` (0.01%) via `LoanBrokerSet`.
2. Originate a large loan (principal ≈ 1e18) via a Batch transaction so the inner `LoanSet` does not need a counterparty signature; this pushes `sfDebtTotal.exponent()` to 6+ and sets `loanScale = 6`.
3. Verify via `ledger_entry` that `sfDebtTotal.exponent() == 6` and note the loan's `sfLoanScale`.

## Calculate Rounding Gap
1. Compute true minimum cover: `TrueMinimum = sfDebtTotal × CoverRateMinimum / 100000`
2. Compute rounded minimum: `RoundedMinimum = roundToAsset(vaultAsset, TrueMinimum, loanScale)`
3. The rounding gap is `TrueMinimum - RoundedMinimum`, which can be up to ~500,000 units when `loanScale = 6`.

## Exploit the Rounding Slack
1. Deposit first-loss capital so `sfCoverAvailable` equals the true minimum minus a value within the rounding gap (e.g., `TrueMinimum - 400,000`).
2. Verify with `ledger_entry` that `CoverAvailable * 100000 / DebtTotal < 1` (below true minimum) while `CoverAvailable >= RoundedMinimum` (passes rounded check).

## Trigger Payment and Verify Mis-Routing
1. Submit a `LoanPay` transaction:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BORROWER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanPay",
         "Account":"<BORROWER_ACCOUNT>",
         "LoanID":"<LOAN_ID>",
         "Amount":{
           "currency":"USD",
           "issuer":"<ISSUER_ACCOUNT>",
           "value":"1000000"
         }
       }
     }]
   }'
   ```
   The engine result is `tesSUCCESS`.

2. Verify mis-routed fees:
   - Check broker owner balance before payment: `curl ... | jq '.result.account_data.Balance'`
   - Check broker owner balance after payment: should increase by fee amount
   - Check broker ledger entry: `curl ... | jq '.result.node | {CoverAvailable:."CoverAvailable", DebtTotal:."DebtTotal"}'`
   - Compute `CoverAvailable * 100000 / DebtTotal`; it remains < 1 (below true minimum)
   - Confirm `sfCoverAvailable` did not increase (fees went to owner instead of reinforcing cover)

## Validation Checklist
The vulnerability is confirmed when:
- ✅ `loanScale >= 6` (large loan created)
- ✅ `CoverAvailable < TrueMinimumCover` (cover below true minimum)
- ✅ `CoverAvailable >= RoundedMinimumCover` (passes rounded check)
- ✅ Broker owner balance increased by fee amount
- ✅ `sfCoverAvailable` did not increase after payment

This demonstrates fees were paid out even though cover was insufficient, violating the minimum cover policy.
