Title

Freeze enforcement gap in Loan default path allows transfer to deep‑frozen pseudo‑account

Description

Brief/Intro

- When defaulting a loan, the protocol returns First‑Loss Capital from the loan broker’s pseudo‑account to the vault’s pseudo‑account without performing freeze/deep‑freeze checks on either endpoint. This violates the freeze semantics expected for XRPL IOUs/MPTs and can credit assets to an account that should not receive funds.
  Note: This is a policy/compliance violation; value remains inside the vault structure (receiver is the vault pseudo‑account) in this path and is not directly drained to an external account.

Vulnerability Details

- Affected path: Loan default handling inside `LoanManage::defaultLoan`.
  - After computing `defaultCovered`, the code unconditionally transfers assets from the broker pseudo‑account to the vault pseudo‑account via `accountSend` without verifying freeze status:
    - src/xrpld/app/tx/detail/LoanManage.cpp:293
      `return accountSend(view, brokerSle->at(sfAccount), vaultSle->at(sfAccount), STAmount{vaultAsset, defaultCovered}, j, WaiveTransferFee::Yes);`
- Missing checks in preclaim: `LoanManage::preclaim` validates flags, states, and timing but does not call `checkFrozen`/`checkDeepFrozen` for the broker or vault pseudo‑accounts against the vault asset.
  - src/xrpld/app/tx/detail/LoanManage.cpp:72–173
- `accountSend` and underlying credit routines do not enforce freeze by themselves; freeze/authorization is expected to be gated in transaction preclaim logic.
  - src/libxrpl/ledger/View.cpp:2702–2820 (MPT paths), 1880–2060 (IOU credit path)
- Contrast with other flows that explicitly enforce freeze/deep‑freeze before transfers:
  - LoanPay: src/xrpld/app/tx/detail/LoanPay.cpp:198, :203, :260
  - LoanBrokerCoverDeposit: src/xrpld/app/tx/detail/LoanBrokerCoverDeposit.cpp:77–80
  - LoanBrokerCoverWithdraw: src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp:111–114
  - VaultDeposit/VaultWithdraw: src/xrpld/app/tx/detail/VaultDeposit.cpp:137–176, src/xrpld/app/tx/detail/VaultWithdraw.cpp:112–135
- Threat model alignment: breaks “Authorization & Freeze” enforcement across trust boundaries (pseudo‑accounts) identified as a primary security property.

Impact Details

- Selected impact: “A bug in the respective layer 0/1/2 network code that results in unintended primitive behavior with no concrete funds at direct risk.”
- Effects:
  - Violation of issuer freeze policy: assets can be credited to a deep‑frozen receiver (e.g., vault pseudo‑account), undermining compliance controls.
  - Ledger invariants may appear consistent numerically, but policy constraints are bypassed, weakening guarantees relied on by integrators and auditors.
  - Not a direct theft vector in this path; severity categorized as Medium under program guidance.

References

- Default flow and transfer:
  - src/xrpld/app/tx/detail/LoanManage.cpp:292–296
- Missing preclaim freeze checks:
  - src/xrpld/app/tx/detail/LoanManage.cpp:72–173
- Expected freeze/deep‑freeze interfaces:
  - include/xrpl/ledger/View.h:178 (checkFrozen), :287 (checkDeepFrozen)
- Comparative enforcement examples:
  - src/xrpld/app/tx/detail/LoanPay.cpp:198, :203, :260
  - src/xrpld/app/tx/detail/LoanBrokerCoverDeposit.cpp:77–80
  - src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp:111–114
  - src/xrpld/app/tx/detail/VaultDeposit.cpp:137–176
  - src/xrpld/app/tx/detail/VaultWithdraw.cpp:112–135

3. Proof of Concept

Proof of Concept (step‑by‑step explanation)

1) Setup
   - Create a vault V (owner O) with an IOU or MPT asset A and a loan broker B linked to V. Fund the broker’s cover and issue a loan to borrower R.
2) Enforce freeze
   - As the asset issuer, apply freeze/deep‑freeze so that the vault pseudo‑account cannot receive A (e.g., issuer deep‑freezes the trustline to the vault pseudo‑account for IOU, or locks the relevant MPT/uses policy to make receiver deep‑frozen).
3) Trigger default
   - Submit `LoanManage` with `tfLoanDefault` for the active loan once default conditions are met.
4) Observation
   - The default flow calls `accountSend(brokerPseudo, vaultPseudo, STAmount{A, defaultCovered}, ...)` without any preceding `checkFrozen`/`checkDeepFrozen` on the receiver. The transfer succeeds despite the receiver being deep‑frozen.
5) Expected vs actual
   - Expected: transaction rejected with a freeze/deep‑freeze error before applying changes.
   - Actual: transfer proceeds; assets are credited to a frozen receiver, violating freeze semantics.

6) Post‑default freeze confirmation (bypass vs state change)
   - Re‑query the issuer–vault‑pseudo trust line and verify `.freeze == true` remains set after default, showing the freeze policy was bypassed, not altered.

Remediation (recommended)

- Add explicit freeze/deep‑freeze checks in `LoanManage::preclaim` for both broker and vault pseudo‑accounts against `vaultAsset`. Consider a defensive re‑check immediately before `accountSend` in `defaultLoan`.
