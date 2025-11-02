# XRPL Lending Protocol – New Findings

## 1. LoanBrokerCoverWithdraw underestimates minimum cover (High)
**Location.** `src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp` lines 118-129【F:src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp†L118-L129】

**Issue.** When a broker withdraws first-loss capital, the transaction is meant to enforce `CoverAvailable - Amount >= round_up(DebtTotal * CoverRateMinimum)` so that the broker cannot drain capital below the mandated floor. The threat model already calls out the need to scrutinize precision and rounding in lending math for exactly this reason.【F:docs/threat-model.md†L42-L45】 However the implementation calls `roundToAsset` without forcing an upward rounding mode. The `Number` library defaults to `to_nearest`, so any required cover that sits between two representable ledger quanta will be rounded *down* whenever the fractional part is less than 0.5 ulp. An attacker can therefore select an `Amount` that leaves `CoverAvailable - Amount` slightly above the rounded-down value even though it is actually below the true requirement. Because invariants only check that `sfCoverAvailable >= 0`, not that the minimum-rate constraint holds, the withdrawal succeeds and the broker exits the transaction with cover below the mandated floor. This directly violates the intent of the threat model, lets a malicious broker free-ride on under-collateralized positions, and can cascade into liquidation mis-accounting.

**Remediation.** Compute `minimumCover` with an explicit upward guard, e.g. `NumberRoundModeGuard guard(Number::upward);` before calling `roundToAsset`, so the minimum always rounds toward the ceiling.

## 2. LoanBrokerCoverClawback can over-claw capital (High)
**Location.** `src/xrpld/app/tx/detail/LoanBrokerCoverClawback.cpp` lines 131-151【F:src/xrpld/app/tx/detail/LoanBrokerCoverClawback.cpp†L131-L151】

**Issue.** The issuer clawback flow should cap the recovered amount at `CoverAvailable - DebtTotal * CoverRateMinimum`, mirroring the minimum cover rule the threat model warns must be protected against rounding drift.【F:docs/threat-model.md†L42-L45】 The helper correctly computes the numeric `maxClawAmount`, but then converts it to an `STAmount` without constraining rounding. `STAmount` canonicalization also rounds to nearest, so any `maxClawAmount` that is just under a representable precision bucket is rounded *up*. The issuer is therefore allowed to claw back slightly more than the permitted delta, pushing `sfCoverAvailable` below the floor after subtraction. Because neither the clawback preclaim path nor the invariant checks re-validate the minimum-rate condition, the excess clawback succeeds and deprives the vault of first-loss capital that should have remained locked.

**Remediation.** When materializing the clawback amount, wrap the conversion in an explicit downward rounding guard (or call `roundToAsset` with `Number::downward`) so the issuer can never claw more than the exact cap.

## 3. LoanManage default flow under-applies first-loss cover (High)
**Location.** `src/xrpld/app/tx/detail/LoanManage.cpp` lines 166-235.【F:src/xrpld/app/tx/detail/LoanManage.cpp†L166-L235】

**Issue.** When a broker defaults a loan, the protocol must apply first-loss capital before charging the vault, a precision-sensitive guarantee called out in the threat model.【F:docs/threat-model.md†L42-L45】 The default handler computes `defaultCovered` with `roundToAsset` but leaves the rounding mode at the global default (`Number::to_nearest`).【F:src/libxrpl/basics/Number.cpp†L33-L46】【F:include/xrpl/protocol/STAmount.h†L739-L748】 If the calculated coverage (bounded by both the floor and the loss amount) sits between two ledger quanta, this “round to nearest” can round *down*. The code then debits the vault for the remainder via `vaultDefaultAmount = totalDefaultAmount - defaultCovered`, so the vault eats the shortfall even though the broker still has first-loss capital that should have been consumed. No later check restores the missing coverage, so lenders absorb the rounding dust.

**Remediation.** Force an upward rounding guard around the `roundToAsset` call (for example, `NumberRoundModeGuard guard(Number::upward);`) so the broker’s first-loss capital is rounded toward the ceiling and always applied in full before the vault is charged.

## 4. LoanSet borrower reserve check can be bypassed (High)
**Location.** `src/xrpld/app/tx/detail/LoanSet.cpp` lines 343-509, `src/xrpld/app/tx/detail/Transactor.cpp` lines 642-671.【F:src/xrpld/app/tx/detail/LoanSet.cpp†L343-L509】【F:src/xrpld/app/tx/detail/Transactor.cpp†L642-L671】

**Issue.** The threat model highlights borrower reserve enforcement as a critical invariant. In `LoanSet::doApply` the borrower can be a separate `sfCounterparty`, yet the code increments the borrower’s owner count and then verifies the XRP reserve using `mPriorBalance`.【F:src/xrpld/app/tx/detail/LoanSet.cpp†L343-L509】 However `mPriorBalance` is populated from the transaction’s `Account` (the broker owner) during `Transactor::apply`.【F:src/xrpld/app/tx/detail/Transactor.cpp†L642-L671】 As a result, when the borrower is the counterparty with no XRP balance, the reserve check still looks at the broker’s healthy balance and passes. A malicious broker can therefore originate unlimited loans for borrowers that do not meet the ledger reserve, leading to ledger entries that should be impossible and exposing lenders to unrecoverable debt.

**Remediation.** Recompute the reserve check against the borrower’s actual balance (or fetch `borrowerSle->at(sfBalance)` directly) instead of reusing `mPriorBalance`, and abort the transaction if the borrower’s XRP balance cannot satisfy the increased owner count.

## 5. LoanPay routes broker fees to frozen owners (High)
**Location.** `src/xrpld/app/tx/detail/LoanPay.cpp` lines 258-289, `include/xrpl/ledger/View.h` lines 160-196, `src/libxrpl/ledger/View.cpp` lines 348-371.【F:src/xrpld/app/tx/detail/LoanPay.cpp†L258-L289】【F:include/xrpl/ledger/View.h†L160-L196】【F:src/libxrpl/ledger/View.cpp†L348-L371】

**Issue.** Loan payments must not deliver fees to accounts frozen by the issuer, per the lending threat model’s emphasis on asset controls.【F:docs/threat-model.md†L42-L45】 The fee routing logic only checks `isDeepFrozen` before sending fees to the broker owner, skipping `checkFrozen` that enforces standard issuer freezes.【F:src/xrpld/app/tx/detail/LoanPay.cpp†L258-L289】【F:include/xrpl/ledger/View.h†L160-L196】 Because `isDeepFrozen` requires the stricter deep-freeze flag, an owner under a normal freeze still receives fees, draining first-loss cover despite being frozen out of transfers.【F:src/libxrpl/ledger/View.cpp†L348-L371】 Attackers can exploit this by freezing the broker’s trust line and then funneling loan payments, effectively siphoning value that should remain locked as cover.

**Remediation.** Reuse the existing `checkFrozen` helper for the broker owner path (and fail when it returns `tecFROZEN`) so fees are withheld whenever the issuer freeze bit is set.

## 6. LoanPay misroutes fees when cover is below the minimum (High)
**Location.** `src/xrpld/app/tx/detail/LoanPay.cpp` lines 258-433, `include/xrpl/protocol/STAmount.h` lines 739-748, `src/libxrpl/basics/Number.cpp` lines 33-46.【F:src/xrpld/app/tx/detail/LoanPay.cpp†L258-L433】【F:include/xrpl/protocol/STAmount.h†L739-L748】【F:src/libxrpl/basics/Number.cpp†L33-L46】

**Issue.** To protect lenders, broker fees should be diverted into cover whenever `CoverAvailable < DebtTotal * CoverRateMinimum`, exactly the precision-sensitive invariant the threat model warns about.【F:docs/threat-model.md†L42-L45】 The routing logic compares the available cover against a `roundToAsset` result that uses the default “round to nearest” mode.【F:src/xrpld/app/tx/detail/LoanPay.cpp†L258-L289】【F:include/xrpl/protocol/STAmount.h†L739-L748】【F:src/libxrpl/basics/Number.cpp†L33-L46】 If the true minimum sits just above a representable quantum, the comparison sees the rounded-down value and concludes the broker is fully collateralized. The fee is then paid out to the owner and cover is never topped up, leaving the broker under the mandated floor while extracting fees.【F:src/xrpld/app/tx/detail/LoanPay.cpp†L426-L433】 No later invariant restores the missing cover, so the broker can repeatedly exploit fractional deficiencies to siphon funds.

**Remediation.** Compute the minimum with an explicit upward guard (or compare against an upward-rounded `tenthBipsOfValue`) so the fee is withheld whenever the true requirement is not met.
