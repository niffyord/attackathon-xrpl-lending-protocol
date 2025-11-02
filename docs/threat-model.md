# XRPL Lending Protocol Threat Model

## 1. Scope and Context

This threat model covers the lending functionality added to the `rippled` server for the XRPL Attackathon. The analysis focuses on the on-ledger lending lifecycle (brokers, loans, vaults, liquidation helpers) and the supporting transaction processing stack that executes XRP Ledger transactions. The XRP Ledger is operated by a decentralized set of peer-to-peer nodes, with consensus used to confirm transactions without a central operator.【F:README.md†L3-L30】 The `rippled` server exposes command-line and RPC interfaces for administrators and clients, expanding the attack surface to include remote method invocation and operational tooling.【F:src/xrpld/app/main/Main.cpp†L125-L188】

The lending protocol is only enabled when the Single Asset Vault (SAV) amendment is active, creating a dependency chain that must be respected in all threat considerations.【F:src/xrpld/app/misc/detail/LendingHelpers.cpp†L26-L31】 Security objectives for this codebase include preserving ledger integrity, preventing unauthorized fund movement, protecting lender and borrower accounting, and ensuring compliance controls tied to vault withdrawals and pseudo-accounts.

## 2. System Overview

`rippled` maintains ledger state through structured ledger objects and transaction processors:

- **Transaction framework** – The `Transactor` base class enforces signature and authorization policies before calling operation-specific `doApply()` logic. Pseudo accounts, which represent objects such as vaults, are barred from signing transactions when the lending protocol is enabled, preventing direct manipulation of lending entities via standard account keys.【F:src/xrpld/app/tx/detail/Transactor.cpp†L674-L721】
- **Pseudo account management** – Ledger helper routines create pseudo accounts with restricted capabilities (no master key, deposit authorization enforced) for features like vaults, linking them to owner objects and ensuring predictable sequence handling under the lending and SAV amendments.【F:src/libxrpl/ledger/View.cpp†L1260-L1303】
- **Loan computation utilities** – `LendingHelpers` define the data model for loan payments, properties, and state tracking. They provide arithmetic utilities for periodic rate calculation, fee separation, and interest accrual, ensuring consistent rounding behavior for ledger accounting.【F:src/xrpld/app/misc/LendingHelpers.h†L37-L161】【F:src/xrpld/app/misc/detail/LendingHelpers.cpp†L57-L191】
- **Vault operations** – Vault transactions (e.g., `VaultWithdraw`) enforce withdrawal policies, asset authorization, and share-to-asset conversion, integrating compliance checks such as credential validation and frozen asset enforcement before releasing funds.【F:src/xrpld/app/tx/detail/VaultWithdraw.cpp†L33-L191】
- **Invariant enforcement** – Post-transaction invariant checks validate that loan brokers and loans remain in a consistent state, forbidding negative balances, preventing sequence rollbacks, and ensuring directories for zero-owner brokers remain well formed.【F:src/xrpld/app/tx/detail/InvariantCheck.cpp†L2359-L2519】

## 3. Assets and Trust Boundaries

| Asset / Component | Description | Security Objectives | Relevant Code |
| --- | --- | --- | --- |
| Loan Ledger Entries | Track outstanding principal, interest, fees, and payment status for each loan. | Prevent negative balances, ensure overpayment flags mutate only via sanctioned flows, guarantee payment completion sets principal to zero. | `LoanState` structures and invariant checks.【F:src/xrpld/app/misc/LendingHelpers.h†L95-L140】【F:src/xrpld/app/tx/detail/InvariantCheck.cpp†L2489-L2519】 |
| Loan Broker Entries | Represent broker-managed positions, cover reserves, and directories. | Maintain monotonically increasing sequence numbers, non-negative debt/cover, and valid directory layouts. | Broker invariant validation.【F:src/xrpld/app/tx/detail/InvariantCheck.cpp†L2359-L2460】 |
| Vault Ledger Entries | Hold collateral assets and share issuance for lenders. | Enforce withdrawal policy, asset authorization, share/account freezes, and precise conversion between shares and assets. | `VaultWithdraw` checks and conversions.【F:src/xrpld/app/tx/detail/VaultWithdraw.cpp†L59-L191】 |
| Pseudo Accounts | System-owned accounts for vaults and similar constructs. | Ensure they cannot initiate transactions or receive unauthorized deposits. | Pseudo-account creation and signature gating.【F:src/libxrpl/ledger/View.cpp†L1260-L1299】【F:src/xrpld/app/tx/detail/Transactor.cpp†L686-L691】 |
| Transaction Processing Stack | RPC/CLI entry points and ledger execution context. | Require authenticated usage, protect against malformed transaction payloads, and prevent DoS through invalid command usage. | RPC command surface.【F:src/xrpld/app/main/Main.cpp†L125-L188】 |

Trust boundaries exist between external clients (RPC/CLI users), peer validators, lending operators (brokers, vault managers), and automated invariant enforcement inside the ledger application. Pseudo accounts and vault share issuances operate under controlled internal policies but interact with user-supplied transactions, making validation layers critical.

## 4. Threat Scenarios

1. **Unauthorized lending transactions** – Attackers may try to submit transactions as pseudo accounts or bypass dependency checks. The transactor signature gating and amendment dependency checks mitigate this, but testing should cover scenarios where feature gating flags are toggled or misapplied.【F:src/xrpld/app/tx/detail/Transactor.cpp†L686-L691】【F:src/xrpld/app/misc/detail/LendingHelpers.cpp†L26-L31】
2. **Loan accounting manipulation** – Incorrect rounding or interest calculations could skew borrower obligations. Threats include forced overflows, precision loss, or inconsistent rounding between helper functions and transaction logic. The helper utilities enforce upward rounding of periodic payments and provide deterministic breakdowns; fuzzing and unit tests should stress boundary values and large scales.【F:src/xrpld/app/misc/LendingHelpers.h†L37-L161】【F:src/xrpld/app/misc/detail/LendingHelpers.cpp†L57-L173】
3. **Invariant bypass or ledger corruption** – If transactions can bypass invariant checks, negative balances or inconsistent directories may persist, enabling fund misallocation or phantom collateral. Focus testing on transaction sequences that delete brokers, adjust owner counts, or manipulate loan payment states.【F:src/xrpld/app/tx/detail/InvariantCheck.cpp†L2359-L2519】
4. **Vault withdrawal abuse** – Malicious users could attempt to withdraw frozen assets, bypass authorization, or exploit share conversion rounding. Investigate edge cases in `VaultWithdraw` for zero-value shares, large share conversions, and credential bypass attempts.【F:src/xrpld/app/tx/detail/VaultWithdraw.cpp†L59-L191】
5. **Cross-feature interactions** – Lending depends on SAV and MPToken features; mismatched feature activation could expose states where invariants or authorization checks are absent. Validate upgrade/downgrade paths and ensure dependency checks run during amendment transitions.【F:src/xrpld/app/misc/detail/LendingHelpers.cpp†L26-L31】【F:src/xrpld/app/misc/LendingHelpers.h†L163-L191】
6. **Operational attacks via RPC/CLI** – Flooding administrative interfaces with malformed commands or unauthorized usage could degrade service or manipulate ledger state if configuration controls are weak. Harden deployments by restricting RPC exposure and monitoring privileged commands enumerated in the main entrypoint.【F:src/xrpld/app/main/Main.cpp†L125-L188】

## 5. Recommended Investigation Areas

- **Precision and overflow testing** across all `Number` operations used in loan and vault math to ensure ledger state remains canonical even under extreme values.【F:src/xrpld/app/misc/detail/LendingHelpers.cpp†L57-L191】
- **Invariant enforcement robustness**, including scenarios with concurrent amendments, ledger rollbacks, or partial transaction failure, to confirm negative states cannot persist.【F:src/xrpld/app/tx/detail/InvariantCheck.cpp†L2359-L2519】
- **Authorization and compliance controls** in vault interactions, especially around `requireAuth` and frozen asset checks, to avoid bypasses when destination accounts or shares change mid-transaction.【F:src/xrpld/app/tx/detail/VaultWithdraw.cpp†L109-L191】
- **Dependency gating** to confirm that lending features cannot activate without SAV prerequisites, and that deactivation safely halts lending transactions without leaving orphaned pseudo accounts.【F:src/xrpld/app/misc/detail/LendingHelpers.cpp†L26-L31】【F:src/libxrpl/ledger/View.cpp†L1283-L1299】
- **RPC surface hardening** through rate limiting and input validation, acknowledging the broad command set available to remote operators.【F:src/xrpld/app/main/Main.cpp†L125-L188】

This threat model should evolve alongside code changes, new amendments, and audit findings discovered during the Attackathon.
