# Additional Freeze Enforcement Vulnerabilities (Nov 2025)

## Context and Threat Model Alignment
- Scope: core XLS-66 lending flows (`LoanBrokerDelete`, `LoanBrokerCoverWithdraw`, `LoanSet`).
- Threat model references: “Misuse of pseudo-accounts to circumvent recipient freeze checks” and “Broker cover withdrawals/fee routing” in `THREAT_MODEL.md`.
- Prior art: Not listed in `SUBMITTED_ISSUES.md`; these are distinct from the previously reported fee-routing and rounding bugs.

## Finding 1 — LoanBrokerDelete bypasses issuer freeze on broker owner (High)
- **Impact:** Frozen broker owners can drain first-loss capital by deleting the broker, despite issuer freezes meant to hold those funds.
- **Attack preconditions:**
  1. Vault issuer freezes the owner’s trust line (set `lsfLowFreeze/lsfHighFreeze`); deep freeze is *not* required.
  2. Broker keeps cover (`sfCoverAvailable > 0`) and clears `sfOwnerCount` by repaying loans/withdrawing debts.
  3. Owner submits `LoanBrokerDelete`.
- **Exploit steps:**
  1. Call `LoanBrokerDelete` with the broker ID.
  2. `preclaim` allows the transaction because no freeze check is performed.
  3. `doApply` executes `accountSend` from the pseudo-account to the frozen owner, releasing the full cover.
- **Why it works:**
  - `LoanBrokerDelete::preclaim` only verifies ownership and `sfOwnerCount`, omitting `checkFreeze`/`checkDeepFrozen` for the owner.
  - `LoanBrokerDelete::doApply` issues an unconditional `accountSend` of `sfCoverAvailable` to the owner, bypassing freeze enforcement (`checkFreeze` is never called in this path).
- **Threat model tie-in:** Violates the objective “Honor issuer/account freeze… semantics,” letting pseudo-accounts circumvent freezes.

## Finding 2 — LoanBrokerCoverWithdraw ignores issuer freeze on destinations (High)
- **Impact:** Broker owners can route first-loss capital to any account that the issuer froze (including themselves) by using `LoanBrokerCoverWithdraw` with `Destination`, draining protected funds.
- **Attack preconditions:**
  1. Issuer freezes the trust line for the intended recipient (e.g., the broker owner) without deep freezing it.
  2. Broker cover remains above the rounded minimum so `LoanBrokerCoverWithdraw` passes other balance checks.
- **Exploit steps:**
  1. Submit `LoanBrokerCoverWithdraw` specifying `Amount` and a `Destination` that is currently frozen but not deep-frozen.
  2. `preclaim` calls `checkDeepFrozen` on the destination but never calls `checkFreeze`, so the frozen trust line is not blocked.
  3. `doApply` transfers the funds either via direct `accountSend` (to self) or through the payment engine, delivering cover despite the freeze.
- **Why it works:**
  - The freeze check block only invokes `checkFrozen` for the pseudo-account (source) and `checkDeepFrozen` for the destination. Normal freeze flags (`lsfLowFreeze/lsfHighFreeze`) on the destination are never examined.
  - For self-withdrawals (`destination == owner`), the same gap applies because the destination path still lacks `checkFreeze`.
- **Threat model tie-in:** Matches the “Broker cover: deposits/withdrawals” attack surface and the listed risk of bypassing recipient freeze checks.

## Finding 3 — LoanSet origination fees ignore issuer freeze on broker owner (Medium/High)
- **Impact:** Issuers cannot prevent a frozen broker owner from collecting origination fees during loan creation; the fee bleeds out of the vault even when the owner is frozen.
- **Attack preconditions:**
  1. Vault issuer freezes the broker owner’s trust line (not deep-frozen).
  2. Loan parameters include `LoanOriginationFee` > 0.
- **Exploit steps:**
  1. Submit `LoanSet` for a new loan with a positive origination fee.
  2. `preclaim` only checks `checkDeepFrozen` on the broker owner; a normal freeze passes.
  3. `doApply` calls `accountSendMulti` to pay the origination fee to the owner, crediting the frozen trust line.
- **Why it works:**
  - `LoanSet::preclaim` uses `checkDeepFrozen` for the broker owner instead of `checkFreeze`, so non-deep freezes are ignored.
  - The ensuing `accountSendMulti` has no additional freeze guard, so the fee transfer succeeds.
- **Threat model tie-in:** Breaks the “Loan lifecycle: creation” control and mirrors the highlighted concern about pseudo-accounts bypassing freeze enforcement.

## Recommended Mitigations
- Apply `checkFreeze` (alongside existing deep-freeze checks) before every value transfer to broker owners or arbitrary destinations in lending flows.
- Centralize freeze enforcement for pseudo-account → owner payments to avoid repeat gaps.
- Extend regression tests to cover issuer freeze scenarios for `LoanBrokerDelete`, `LoanBrokerCoverWithdraw`, and `LoanSet`.


