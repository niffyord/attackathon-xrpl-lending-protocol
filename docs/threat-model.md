## XRPL Lending Protocol Threat Model (XLS-66)

### Scope and Sources

- In-scope code: core `rippled` lending protocol and dependencies in this repository: `src/xrpld/app/tx/detail/*Loan*`, `src/xrpld/app/misc/*Lending*`, `src/libxrpl/ledger/*`, `include/xrpl/protocol/**/*` (including `detail/*.macro`).
- Program docs: `docs/ATTACKATHON.md` (lines 1–75) and repo `README.md` (lines 1–72) for objectives and constraints.

### Security Objectives

- Protect lender funds and borrower repayments; no unauthorized value creation, destruction, or transfer.
- Enforce vault First Loss Capital (FLC) coverage and fair liquidation semantics.
- Ensure interest, fees, and rounding are consistent and resistant to manipulation across scales.
- Honor issuer/account freeze and deep-freeze semantics and permitted clawback policy.
- Maintain ledger consistency: loan/broker/vault state transitions are atomic and invariant-safe.
- Prevent privilege abuse by brokers/admins; respect access controls and configuration governance.

### Architecture & Trust Boundaries

- Transactions: `Transactor` pipeline per operation: `preflight` (syntax/rules), `preclaim` (state checks), `doApply` (state mutation). Examples: `LoanSet`, `LoanPay`, `LoanManage`, `LoanBroker*`, `Vault*` in `src/xrpld/app/tx/detail/`.
- Helpers: `LendingHelpers.*` centralize rate/rounding, fee/interest splits, state calculations.
- Ledger state: `SLE` entries for `Loan`, `LoanBroker`, `Vault`, balances and trust lines.
- Payments: IOU/MPT transfers via `accountSend`/`accountSendMulti` and `Payment` engine. Freeze and deep-freeze checks occur in step checks and path engine.
- Protocol surfaces: macros define transactions, fields, flags: `include/xrpl/protocol/detail/{features.macro, transactions.macro, ledger_entries.macro, sfields.macro}`.
- External boundary: JSON-RPC admission and consensus; only sanctioned devnet/standalone per program rules.

### Protected Assets and Critical Invariants

- Vault assets and shares: conservation except when explicitly minted/burned per rules; shares track pro-rata claims over vault assets.
- Loan values: `TotalValueOutstanding = PrincipalOutstanding + InterestOutstanding`; decreases only by valid repayments/default handling.
- Broker state: `DebtTotal`, `CoverAvailable`, coverage floors derived from configuration (`CoverRateMinimum`, `CoverRateLiquidation`).
- Rounding/scales: rounding must never understate required coverage or misallocate interest/fees.
- Compliance: freeze/deep-freeze/clawback flags must be enforced on all value flows (owner and pseudo accounts).

### Primary Attack Surfaces

- Loan lifecycle: creation (`LoanSet`), payment (`LoanPay`), impairment/default (`LoanManage`), deletion.
- Broker cover: deposits/withdrawals (`LoanBrokerCoverDeposit/Withdraw`), fee routing during `LoanPay`.
- Vault operations: creation, clawback, withdraw; share mint/burn; reward/interest flows.
- Payment engine interactions: multi-destination (`accountSendMulti`), pathfinding, transfer fees.
- Rounding and number scale: `Number`, `roundToAsset`, loan/vault scale mismatches.
- Freeze/deep-freeze/clawback enforcement across owner/pseudo accounts, IOU vs MPT flows.
- Macro-defined fields and flags: malformed/edge configurations, rule gating (`featureClawback`, etc.).

### Threats and Abuse Cases (STRIDE-style)

- Spoofing/Privilege
  - Broker-originated loans bypassing borrower reserve or signature requirements in `LoanSet`.
  - Misuse of pseudo-accounts to circumvent recipient freeze checks.
  - Mitigations: `Transactor` prechecks; `requireAuth` for MPT; explicit borrower countersignature path; reserve checks in base `Transactor` and `Payment` engine.

- Tampering with Value Flows
  - Fee routing on `LoanPay` ignoring issuer freeze on broker owner trust line, sending fees to owner instead of reinforcing cover when frozen.
  - Cover withdrawal below floor via rounding-down of minimum coverage; FLC siphoning during `LoanBrokerCoverWithdraw`.
  - Liquidation/default amounts computed with coarse scale, enabling strategic rounding gaps to manipulate who bears losses.
  - Mitigations to enforce: use freeze checks for both freeze and deep-freeze on owner, compute cover with vault precision and non-downward rounding, centralize floor logic reused by fees/withdraw/default.

- Repudiation
  - Ambiguity in rounding mode across functions; different modes (`to_nearest`, `downward`, implicit STAmount) can cause disputable state deltas.
  - Mitigation: document and enforce a single rounding policy per invariant; wrap with guards.

- Information Disclosure
  - Not primary; ledger is public. Ensure no leakage of secrets via RPC logs; keep PII out of on-ledger memo fields.

- Denial of Service (logical)
  - Transactions that always tec-claim or loop through path engine with constrained assets; large-scale rounding-induced retries.
  - Mitigations: early `preclaim` gating; avoid invoking path engine when unnecessary (direct sends where possible); cap computational paths.

- Elevation of Privilege
  - Broker/admin can set parameters causing invariant erosion (e.g., `CoverRateMinimum` to 0, disabling fees or bypassing protections).
  - Mitigation: parameter bounds in `preflight/preclaim`, rule gates from macros/features, require issuer permissions for clawback.

### Concrete Vulnerability Themes Observed in Code

- Fee routing vs. freeze semantics (high impact)
  - `LoanPay` computes `sendBrokerFeeToOwner` using coverage floor and only checks deep freeze for owner, not normal freeze. When issuer freeze is set but not deep freeze, fees may still route to owner, bypassing issuer intent.
  - Relevant files: `src/xrpld/app/tx/detail/LoanPay.cpp` (broker fee routing); freeze utilities in `src/xrpld/app/paths/detail/StepChecks.h` and helpers.
  - Recommended: apply unified `checkFreeze/checkDeepFrozen` on the exact sender→owner asset flow; on failure, redirect to cover or abort consistently.

- Rounding-driven coverage underflow (critical/high)
  - Minimum cover and default coverage computed with `roundToAsset(..., loanScale)` can round down when vault precision is higher, enabling cover to drift below true minimum while predicates still pass.
  - Relevant files: `LoanPay.cpp` (min cover for fee routing), `LoanBrokerCoverWithdraw.cpp` (min cover during withdraw), `LoanManage.cpp` (default coverage), `LendingHelpers.cpp` (scale selection and rounding strategy).
  - Recommended: compute floors in vault asset precision with upward or to-nearest rounding; centralize floor computation and reuse everywhere.

- Reserve check and borrower validation in broker-originated loans (high)
  - Ensure `LoanSet` enforces borrower reserve and countersignature across all branches; validate vault pseudo-account freeze status and issuer permissions.
  - Relevant files: `LoanSet.cpp`, `Transactor.h`, `Payment` usage; freeze checks in `LoanSet.cpp` before value movements.

- Clawback and compliance primitives (medium/high)
  - `VaultClawback` requires issuer and flags (`lsfAllowTrustLineClawback`, no `lsfNoFreeze`); MPT needs `lsfMPTCanClawback`. Inconsistent enforcement in other flows could reintroduce value to frozen holders indirectly.
  - Recommended: extend clawback/freeze checks to all intermediate flows (owner↔pseudo, broker↔vault) and forbid configurations that cannot be clawed back (e.g., pseudo-account issuers in vault assets) — already partially present in `VaultCreate`.

- Multi-destination transfers and path engine interactions (medium)
  - `accountSendMulti` and Payment engine must uniformly enforce freeze/authorization/fee handling for IOU and MPT; divergence can create bypasses.
  - Recommended: centralize enforcement in ledger layer helpers invoked by all payment paths.

### Controls and Mitigations Present

- Freeze/deep-freeze checks: step checks and transaction code gate sends and receives; deep-freeze and global freeze honored; issuer special-cases.
- Rule/feature gating: `featureClawback`, other protocol features guard behavior and flags surfaced in RPC.
- Clawback constraints: only issuer, not XRP, flags required for IOU/MPT; vault creation disallows pseudo-account issuers for clawback-ability.
- Transactor pipeline: strict `preflight`/`preclaim` before `doApply`; state changes are atomic via `ApplyView`.
- Rounding helpers: `LendingHelpers` consolidates computations; use of `STAmount` rounding to set loan scale.

### Highest-Priority Risks to Target

1) Coverage floor underflow via rounding (drives fee diversion and unsafe withdraws).
2) Freeze check gaps on fee routing to owner during `LoanPay`.
3) Liquidation/default computations using coarse `loanScale` causing unfair outcomes.
4) Broker-originated `LoanSet` reserve/countersignature edge cases.
5) Incomplete enforcement of clawback/freeze along owner↔pseudo flows and Payment engine paths.

### Recommended Hardening

- Unify coverage floor computation at vault precision with upward/to-nearest rounding; reuse in fee routing, withdraw, default, and liquidation.
- Apply `checkFreeze` and `checkDeepFrozen` to all relevant fee/cover flows, including broker owner trust line in `LoanPay`.
- Validate borrower reserves and countersignatures in all `LoanSet` branches; audit `Transactor` balance assumptions like `mPriorBalance`.
- Extend negative tests for deep-freeze and clawback across IOU/MPT and pseudo/owner permutations; add invariant checks in tests.
- Document and enforce rounding policy per computation; add guards preventing zero-effect payments from accumulating rounding drift.

### Testing and PoC Guidance

- Use sanctioned devnet or standalone node (Option B in program docs): submit real transactions via JSON-RPC; demonstrate invariant breaks via `ledger_entry`, `account_lines`.
- Construct adversarial scales by mixing large and small loans to stress `loanScale` vs vault precision; validate coverage predicates against analytic values.
- Freeze issuer↔owner trust lines and validate fee routing and cover reinforcement behaviors under `LoanPay`.
- Exercise `LoanBrokerCoverWithdraw` across the minimum coverage boundary; confirm behavior with path engine vs direct send branches.

### Appendix: Key Files and Components (non-exhaustive)

- Transactions: `src/xrpld/app/tx/detail/LoanSet.cpp`, `LoanPay.cpp`, `LoanManage.cpp`, `LoanBroker{Set,CoverDeposit,CoverWithdraw,Delete}.cpp`, `Vault{Create,Withdraw,Clawback}.cpp`.
- Helpers: `src/xrpld/app/misc/LendingHelpers.h`, `src/xrpld/app/misc/detail/LendingHelpers.cpp`.
- Payments: `src/libxrpl/ledger/View.cpp` (`accountSend`, `accountSendMulti`), `src/xrpld/app/tx/detail/Payment.cpp` and step checks `src/xrpld/app/paths/detail/StepChecks.h`.
- Protocol/macros: `include/xrpl/protocol/detail/{features.macro, transactions.macro, ledger_entries.macro, sfields.macro}`; formats: `TxFormats.h`, `LedgerFormats.h`.
- Number and rounding: `src/libxrpl/basics/Number.cpp`, `include/xrpl/protocol/STAmount.h`.

### Context Sources

- `docs/ATTACKATHON.md` (lines 1–75): program scope, priorities, testing rules.
- `README.md` (lines 1–72): XRPL and `rippled` overview and features.


