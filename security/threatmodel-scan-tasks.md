# XRPL Lending Protocol – Targeted Vulnerability Scan Tasks

The tasks below align with the components defined in `threatmodel.md`. Each task package is scoped so a reviewer can dive deeply into code, math helpers, and ledger flows to validate the associated invariants and uncover novel vulnerabilities (beyond the existing findings). For every task, investigators should trace control flow end-to-end, validate all rounding/authorization paths, and cross-check ledger invariants.

## 1. Amendment & Feature Gating
- **Scope.** `src/xrpld/app/misc/detail/LendingHelpers.cpp`, `src/xrpld/app/tx/detail/VaultCreate.cpp`, `src/xrpld/app/tx/detail/Loan*.cpp`, `src/xrpld/app/tx/detail/Vault*.cpp`, feature flag plumbing in `src/xrpld/protocol/Feature.cpp`, and any documentation that references lending feature activation.
- **Objectives.**
  - Trace `checkLendingProtocolDependencies` across all call sites; ensure amendments and feature bits can never be bypassed or misconfigured during transaction preflight.
  - Validate that pseudo-account helpers and issuer/domain lookups enforce permissions under partial amendment activation or downgrade scenarios.
  - Model edge cases where new amendments interact with lending dependencies and confirm no missing guard rails.
- **Deliverables.** Enumerate any pathways that allow lending transactions without the full amendment set, or that permit spoofed issuers/domains during activation.

## 2. Single Asset Vault Subsystem
- **Scope.** `src/xrpld/app/tx/detail/VaultCreate.cpp`, `VaultDeposit.cpp`, `VaultWithdraw.cpp`, `VaultClawback.cpp`, vault math helpers under `src/xrpld/app/misc/detail`, and SAV share math in `src/libxrpl`.
- **Objectives.**
  - Reconcile share ↔ asset conversions and dust handling, reviewing every rounding guard and overflow check.
  - Validate freeze/authorization enforcement, including recursive deep-freeze propagation, limit orders, and multi-hop withdrawals via the Payment engine.
  - Inspect vault state transitions (creation, deposit, withdraw, clawback) to ensure post-transaction invariants prevent under-collateralized vaults or double withdrawals.
- **Deliverables.** Report exploitable rounding, authorization, or invariant gaps allowing asset leakage or unauthorized redemption.

## 3. Loan Broker & Cover Management
- **Scope.** `LoanBroker*.cpp` transactions, cover math helpers, `include/xrpl/ledger/View.h`, invariant enforcement for brokers in `src/xrpld/app/tx/detail/InvariantCheck.cpp`, and Number/STAmount utilities.
- **Objectives.**
  - Audit cover requirement calculations and conversions, ensuring all comparisons round conservatively (upward for minimum cover, downward for clawbacks).
  - Follow cover deposits/withdrawals/clawbacks through Payment engine paths to confirm freeze, authorization, and pseudo-account constraints.
  - Stress-test issuer and broker-controlled flows for precision exploits, race conditions, or directory inconsistencies.
- **Deliverables.** Document any paths that let brokers drain cover, issuers over-claw funds, or bypass reserve/reserve-increase requirements.

## 4. Loan Lifecycle Processing
- **Scope.** `LoanSet.cpp`, `LoanPay.cpp`, `LoanManage.cpp`, lending helpers in `src/xrpld/app/misc/LendingHelpers.h` & `.cpp`, and payment scheduling utilities.
- **Objectives.**
  - Validate borrower reserve accounting, signature requirements, and sequencing for loan origination/updates.
  - Recompute periodic payment math, interest accrual, impairment handling, and default flows for rounding or sequencing bugs.
  - Analyze fee routing logic when cover is deficient, borrowers are frozen, or loans change status mid-ledger close.
- **Deliverables.** Identify exploits that allow borrowers or brokers to underpay, reroute fees, or evade impairment/default safeguards.

## 5. Ledger Invariants & Pseudo-Account Framework
- **Scope.** `src/xrpld/app/tx/detail/InvariantCheck.cpp`, pseudo-account helpers in `src/xrpld/app/misc` and `include/xrpl/protocol`, directory management in `include/xrpl/ledger/View.h` and `src/libxrpl/ledger/View.cpp`.
- **Objectives.**
  - Confirm invariant visitors trigger for every lending-related ledger modification and reject malformed pseudo-accounts or stale directories.
  - Inspect keylet/directory traversal for ways to orphan pseudo-accounts, bypass owner reserve tracking, or write inconsistent state.
  - Evaluate amendment disable/re-enable scenarios to ensure invariants persist whenever lending objects exist.
- **Deliverables.** Surface invariant gaps or ledger write sequences that corrupt broker/vault/loan records without detection.

Each task should culminate in a written assessment with proof-of-concept ledger flows (where applicable), highlighting concrete vulnerabilities or confirming the absence of issues after exhaustive review.
