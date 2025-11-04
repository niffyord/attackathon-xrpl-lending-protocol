# Validation Log — Additional Freeze Enforcement Vulnerabilities (Nov 2025)

## Scope and Approach
- Reviewed XLS-66 lending transaction sources under `src/xrpld/app/tx/detail/` with emphasis on `LoanBrokerDelete`, `LoanBrokerCoverWithdraw`, and `LoanSet` to cross-check freeze enforcement at `preclaim` and `doApply` stages.
- Cross-referenced freeze helper semantics in `include/xrpl/ledger/View.h` and transfer primitives in `src/libxrpl/ledger/View.cpp` to confirm which flags (`lsfLowFreeze/lsfHighFreeze` vs. deep-freeze) each helper enforces.
- Consulted the threat model (`docs/threat-model.md`) to align expected controls around issuer freezes and pseudo-account flows.

## Finding 1 — LoanBrokerDelete bypasses issuer freeze on broker owner
**Status:** Confirmed. Exploitable.
- `LoanBrokerDelete::preclaim` only checks broker ownership and `sfOwnerCount`; no `checkFrozen` or `checkDeepFrozen` guard is invoked on the owner prior to deletion.【F:src/xrpld/app/tx/detail/LoanBrokerDelete.cpp†L39-L63】
- During `doApply`, the implementation calls `accountSend` to transfer the broker's entire `sfCoverAvailable` balance from the pseudo-account to the owner without any intermediate freeze validation.【F:src/xrpld/app/tx/detail/LoanBrokerDelete.cpp†L103-L114】
- The `checkFrozen` helper enforces issuer-level freezes (including `lsfLowFreeze/lsfHighFreeze`), whereas `checkDeepFrozen` alone would miss them.【F:include/xrpl/ledger/View.h†L178-L200】 Because neither helper is called, a trust line frozen by the issuer still receives funds when the broker is deleted. `accountSend` delegates to `rippleCreditIOU` without performing additional freeze checks, so the transfer succeeds once invoked.【F:src/libxrpl/ledger/View.cpp†L1908-L2049】
- Threat model alignment: the threat model explicitly calls out misuse of pseudo-accounts to circumvent recipient freeze checks; this flow violates that expectation.【F:docs/threat-model.md†L1-L84】

**Exploit sketch:** Issuer freezes the broker owner's trust line while cover remains available. The owner repays any outstanding loans to zero `sfOwnerCount`, submits `LoanBrokerDelete`, and receives the frozen cover via the unconditional `accountSend`.

## Finding 2 — LoanBrokerCoverWithdraw ignores issuer freeze on destinations
**Status:** Confirmed. Exploitable.
- `LoanBrokerCoverWithdraw::preclaim` verifies `checkFrozen` for the pseudo-account (source) but only applies `checkDeepFrozen` to the destination account, omitting the normal freeze check that catches issuer `lsfLowFreeze/lsfHighFreeze` flags.【F:src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp†L100-L140】
- In `doApply`, both the self-transfer branch (`accountSend`) and the payment-engine branch execute without any extra freeze guard, so a merely frozen (but not deep-frozen) destination receives the cover withdrawal.【F:src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp†L164-L200】【F:src/libxrpl/ledger/View.cpp†L1908-L2049】
- Since `checkDeepFrozen` only blocks deep-freeze cases, standard freezes are bypassed even though the threat model requires honoring issuer freezes on broker cover flows.【F:include/xrpl/ledger/View.h†L287-L314】【F:docs/threat-model.md†L58-L111】

**Exploit sketch:** Broker owner freezes their own trust line (or any collaborator's). They issue `LoanBrokerCoverWithdraw` targeting the frozen account; `preclaim` passes because only deep-freeze is checked, and `doApply` transfers the funds, draining protected cover.

## Finding 3 — LoanSet origination fees ignore issuer freeze on broker owner
**Status:** Confirmed. Exploitable.
- `LoanSet::preclaim` performs `checkDeepFrozen` on the broker owner but never calls `checkFrozen`, so accounts under a normal issuer freeze are not rejected before loan creation.【F:src/xrpld/app/tx/detail/LoanSet.cpp†L292-L318】
- When an origination fee is configured, `LoanSet::doApply` uses `accountSendMulti` to pay the broker owner alongside the borrower, again without additional freeze enforcement on the owner path.【F:src/xrpld/app/tx/detail/LoanSet.cpp†L520-L563】 The underlying send path shares the same lack of freeze checks noted above.【F:src/libxrpl/ledger/View.cpp†L1908-L2049】
- Because `checkDeepFrozen` only blocks deep freezes, a standard issuer freeze still allows the origination fee to escape, contrary to the threat model’s requirement to honor freeze semantics during loan creation flows.【F:include/xrpl/ledger/View.h†L287-L314】【F:docs/threat-model.md†L58-L111】

**Exploit sketch:** Vault issuer freezes the broker owner’s trust line. The broker originates a new loan with a positive origination fee. `LoanSet` admits the transaction and sends the fee to the frozen owner, leaking first-loss capital.

## Overall Assessment
All three findings reproduce the same control gap: lending transactions rely on callers to enforce issuer freeze semantics, but several owner/destination paths only check for deep freeze (or nothing). Given the direct value transfers in `doApply`, each issue is valid and practically exploitable under the documented threat model. Recommended mitigations match the reporter’s suggestion: invoke `checkFreeze` before every pseudo-account→owner/destination payment and extend regression coverage for freeze scenarios.
