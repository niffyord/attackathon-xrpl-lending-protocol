# Fee routing ignores issuer freeze on broker trust line, letting frozen brokers siphon first-loss capital

**Severity:** High  
**Impact:** Drainage of first-loss capital despite issuer-imposed freezes

## Brief/Intro

`LoanPay::doApply` only checks for deep-freeze status (`isDeepFrozen`) before routing borrower fees to the broker owner. When the issuer freezes the broker’s trust line (`lsfLowFreeze`/`lsfHighFreeze`), the owner should be blocked from receiving tokens. Because the code never calls `checkFrozen`, the fee still transfers, letting a quarantined broker siphon first-loss capital.

## Vulnerability Details

- Location: `src/xrpld/app/tx/detail/LoanPay.cpp` (lines 258-282).

  ```cpp
  bool const sendBrokerFeeToOwner = coverAvailableProxy >=
          roundToAsset(asset,
                       tenthBipsOfValue(
                           debtTotalProxy.value(), coverRateMinimum),
                       loanScale) &&
      !isDeepFrozen(view, brokerOwner, asset);
  auto const brokerPayee =
      sendBrokerFeeToOwner ? brokerOwner : brokerPseudoAccount;
  ```

- The condition never invokes `checkFrozen(view, brokerOwner, asset)` so per-line freezes are ignored.
- The fee moves via `accountSendMulti`, bypassing the normal `rippleCreditIOU` freeze enforcement.
- `checkFrozen` (`include/xrpl/ledger/View.h`) enforces both global and individual freezes; skipping it defeats issuer freeze controls.
- `LoanPay::preclaim` (lines 198-207) only checks whether the borrower account and the vault pseudo-account are frozen; the broker owner never passes through any freeze check at all.

## Impact Details

- Issuers freeze a broker to stop them from extracting fees. The bug still routes the full broker fee to the frozen owner on every payment.
- Those fees come directly out of borrower payments that should reinforce `sfCoverAvailable`, draining first-loss capital and weakening lender protection.
- Matches High severity: “Drainage and/or stealing of funds from ledger objects (vault, first loss capital).”

## References

- `LoanPay::doApply`: https://github.com/immunefi-team/attackathon-xrpl-lending-protocol/blob/main/src/xrpld/app/tx/detail/LoanPay.cpp#L258-L282
- Freeze helper: https://github.com/immunefi-team/attackathon-xrpl-lending-protocol/blob/main/include/xrpl/ledger/View.h#L177-L197

## Proof of Concept

1. Launch a `rippled` devnet with lending amendments enabled. Create issuer `I`, broker owner `B`, broker pseudo account, and borrower `U`. Originate a loan where `sfCoverAvailable` is well above the threshold so `sendBrokerFeeToOwner` evaluates to true.
2. Freeze the issuer->broker trust line:

   ```json
   {
     "TransactionType": "TrustSet",
     "Account": "<ISSUER_ACCOUNT>",
     "LimitAmount": {
       "currency": "USD",
       "issuer": "<BROKER_OWNER>",
       "value": "0"
     },
     "Flags": 2147483648
   }
   ```

   Confirm the freeze flag via `account_lines`.

3. Submit a `LoanPay` transaction from borrower `U`.
4. The transaction succeeds (`tesSUCCESS`) and the broker owner’s IOU balance increases by the fee amount despite the freeze. No `tecFROZEN` error occurs.
5. Observe that `sfCoverAvailable` does not increase (the fee left the FLC pool) while the broker owner’s balance grew. Expected behaviour: the payment should fail—or at least leave the fee in cover—whenever an issuer freeze is active.

## Recommendation

Call `checkFrozen(view, brokerOwner, asset)` before routing fees. If the trust line is frozen, treat it as deep-freeze (leave the fee in cover) or revert with `tecFROZEN`, restoring issuer control over frozen brokers.


