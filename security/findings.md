# XRPL Lending Protocol – New Findings

## 1. LoanBrokerCoverWithdraw underestimates minimum cover (High)
**Location.** `src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp` lines 118-129【F:src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp†L118-L129】

**Issue.** When a broker withdraws first-loss capital, the transaction is meant to enforce `CoverAvailable - Amount >= round_up(DebtTotal * CoverRateMinimum)` so that the broker cannot drain capital below the mandated floor. The threat model already calls out the need to scrutinize precision and rounding in lending math for exactly this reason.【F:docs/threat-model.md†L42-L45】 However the implementation calls `roundToAsset` without forcing an upward rounding mode. The `Number` library defaults to `to_nearest`, so any required cover that sits between two representable ledger quanta will be rounded *down* whenever the fractional part is less than 0.5 ulp. An attacker can therefore select an `Amount` that leaves `CoverAvailable - Amount` slightly above the rounded-down value even though it is actually below the true requirement. Because invariants only check that `sfCoverAvailable >= 0`, not that the minimum-rate constraint holds, the withdrawal succeeds and the broker exits the transaction with cover below the mandated floor. This directly violates the intent of the threat model, lets a malicious broker free-ride on under-collateralized positions, and can cascade into liquidation mis-accounting.

**Remediation.** Compute `minimumCover` with an explicit upward guard, e.g. `NumberRoundModeGuard guard(Number::upward);` before calling `roundToAsset`, so the minimum always rounds toward the ceiling.

## 2. LoanBrokerCoverClawback can over-claw capital (High)
**Location.** `src/xrpld/app/tx/detail/LoanBrokerCoverClawback.cpp` lines 131-151【F:src/xrpld/app/tx/detail/LoanBrokerCoverClawback.cpp†L131-L151】

**Issue.** The issuer clawback flow should cap the recovered amount at `CoverAvailable - DebtTotal * CoverRateMinimum`, mirroring the minimum cover rule the threat model warns must be protected against rounding drift.【F:docs/threat-model.md†L42-L45】 The helper correctly computes the numeric `maxClawAmount`, but then converts it to an `STAmount` without constraining rounding. `STAmount` canonicalization also rounds to nearest, so any `maxClawAmount` that is just under a representable precision bucket is rounded *up*. The issuer is therefore allowed to claw back slightly more than the permitted delta, pushing `sfCoverAvailable` below the floor after subtraction. Because neither the clawback preclaim path nor the invariant checks re-validate the minimum-rate condition, the excess clawback succeeds and deprives the vault of first-loss capital that should have remained locked.

**Remediation.** When materializing the clawback amount, wrap the conversion in an explicit downward rounding guard (or call `roundToAsset` with `Number::downward`) so the issuer can never claw more than the exact cap.
