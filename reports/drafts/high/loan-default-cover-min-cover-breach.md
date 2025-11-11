Title

Loan default path fails to re-enforce minimum cover, leaving broker under-collateralized

Description

Brief/Intro

- When a loan is defaulted via `LoanManage::defaultLoan`, the handler transfers first-loss capital (FLC) from the broker pseudo-account back to the vault but never rechecks the broker’s minimum cover requirement. Because the debt total shrinks while cover is reduced by the entire `defaultCovered` amount, the broker can exit the transaction with `sfCoverAvailable` below `sfDebtTotal * CoverRateMinimum`. All remaining loans now lack the mandated first-loss buffer.
- Loan creation (`LoanSet`) and fee routing (`LoanPay`) explicitly enforce the minimum cover invariant, so protocol operators and auditors assume it always holds. Violating it after a default pushes inevitable future losses onto vault depositors and can brick subsequent defaults (`tefBAD_LEDGER`), causing stuck bad debt.

Vulnerability Details

- Affected flow: `LoanManage` with the `tfLoanDefault` flag.
  - After computing `defaultCovered`, the code subtracts it from both `sfCoverAvailable` and `sfDebtTotal` and immediately exits via `accountSend` without ensuring the remaining cover still satisfies the policy:
    - `src/xrpld/app/tx/detail/LoanManage.cpp:167-183`
    - `src/xrpld/app/tx/detail/LoanManage.cpp:257-299`
- The helper `roundToAsset(..., loanScale)` is reused from loan accounting. With mixed-scale portfolios, rounding already truncates the withdrawal to coarse units; after subtraction the remainder can fall below the true minimum even when `defaultCovered` is capped at `tenthBipsOfValue(debt, coverRateMinimum)`.
- No guard recomputes `requiredCover = roundToAsset(vaultAsset, tenthBipsOfValue(brokerDebtTotalProxy.value(), coverRateMinimum), loanScale)` after the debt reduction. `LoanSet::doApply` shows the intended invariant check:
  - `src/xrpld/app/tx/detail/LoanSet.cpp:487-501`
- Result: the broker leaves default handling with insufficient cover and the ledger records an under-collateralized broker as “healthy.”

Impact Details

- Severity: **High** — mandatory first-loss capital backing for the remaining loan book is broken.
- Consequences:
  - Subsequent borrower defaults can no longer seize enough FLC, forcing vault assets to absorb extra losses.
  - Future defaults may revert with `tefBAD_LEDGER` once `coverAvailable` is too small, freezing resolution paths and causing protocol-wide denial of service in stressed scenarios.
  - Attack pattern: broker funds FLC exactly to the minimum, runs a large loan to default, and walks away with a broker object that violates policy while continuing to collect fees or originate additional loans.

References

- Missing invariant enforcement:
  - `src/xrpld/app/tx/detail/LoanManage.cpp:167-183`
  - `src/xrpld/app/tx/detail/LoanManage.cpp:257-299`
- Expected invariant check:
  - `src/xrpld/app/tx/detail/LoanSet.cpp:487-501`
- Rounding helper:
  - `include/xrpl/protocol/STAmount.h:737-752`
- Minimum-cover calculations elsewhere:
  - `src/xrpld/app/tx/detail/LoanPay.cpp:259-276`
  - `src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp:120-130`

Proof of Concept (step-by-step explanation)

1) Setup
   - Create vault V with asset `IOU/USD`, broker B (`CoverRateMinimum = 50%`), and two loans L1 (80 units) plus L2 (20 units). Seed `sfCoverAvailable = 50` to satisfy the minimum against `sfDebtTotal = 100`.
2) Orchestrate default
   - Let the borrower for L1 miss payments until default is allowed. Submit `LoanManage` with `tfLoanDefault`.
3) Observe post-state
   - `LoanManage::defaultLoan` computes `defaultCovered = min(Debt * CoverRateMinimum * CoverRateLiquidation, totalDefault)` which caps at 50. It subtracts 50 from both `sfCoverAvailable` (now 0) and `sfDebtTotal` (now 20) and exits without rechecking the cover floor.
4) Verify invariant break
   - Query the broker ledger entry: `sfCoverAvailable = 0`, `sfDebtTotal = 20`, while policy requires at least 10. The state clearly violates the minimum cover invariant.
5) Secondary effect
   - Force L2 to default. `LoanManage::defaultLoan` now attempts to cover losses but finds `coverAvailable < defaultCovered`, causing `tefBAD_LEDGER`. The bad debt cannot be resolved and vault participants absorb the loss.

Remediation (recommended)

- After updating `sfDebtTotal` and `sfCoverAvailable`, recompute the minimum cover for the new debt total and ensure the broker still satisfies it. Either:
  - Cap `defaultCovered` so that `coverAvailableProxy - defaultCovered >= requiredCover`, or
  - Replenish the shortfall by reducing `defaultCovered` and applying the remainder to `vaultDefaultAmount` so the debt is accurately allocated.
- Preferably centralize minimum-cover enforcement into a helper used by `LoanManage::defaultLoan`, `LoanPay::doApply`, and `LoanBrokerCoverWithdraw::preclaim` to avoid future drift.
