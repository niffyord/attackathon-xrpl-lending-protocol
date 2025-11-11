# XRPL Lending Protocol Attackathon Overview

## Program Snapshot

- **Name:** Attackathon | XRPL Lending Protocol
- **Target:** XRP Ledger (XRPL) native lending protocol (XLS-66)
- **Code Base:** `rippled` (C/C++), ~35k LOC in scope; code frozen during program
- **Timeline:** 27 Oct 2025 14:00 UTC → 24 Nov 2025 14:00 UTC (live window ~26 days)
- **Triaged By:** Immunefi (step-by-step PoC review)
- **Reward Pool:** Flat $200,000 USD (denominated in USD, paid in RLUSD on Ethereum). If no bugs: $30,000 USD.
  - Primary Pool $140k · All Stars Pool $40k · Podium Pool $20k
- **Submission Requirements:** KYC (via Onfido) required; runnable PoC mandatory for all severities
- **Protocol Version:** Initial deployment; SAV and lending protocol are V1 launches
- **Communication:** Questions via Immunefi Discord `#xrpl-attackathon`

## Assets & Scope Highlights

Blockchain/DLT components within the `rippled` repository, including but not limited to:

- Core protocol headers and sources (`xrpl/protocol`, `xrpl/ledger`, `xrpl/json`) such as `json_value`, `ApplyView`, `View`, `Asset`, `Indexes`, and related ledger formats
- Lending protocol logic and helpers (`LendingHelpers`, `Loan*`, `Vault*`, `Transactor`, `Payment`) covering LoanBroker Cover/Withdraw/Clawback/Delete/Set flows plus LoanManage/LoanPay/LoanSet/LoanDelete processors
- Macros defining protocol structures (`features.macro`, `ledger_entries.macro`, `sfields.macro`, `transactions.macro`)
- Application and networking layers (`app/main/Main.cpp`, `misc/NetworkOPs.cpp`, `PeerImp.cpp`, `RPCCall.cpp`)
- Supporting basics (`basics/Number.cpp`, `protocol/STAmount.cpp`, `STObject.cpp`, `STTx.cpp`, etc.)

> Refer to Immunefi scope list for exact paths and keep testing on sanctioned environments only.

## Operational Considerations

- Collateral for institutional borrowers is often held off-chain with custodians (e.g., BitGo); parts of the loan lifecycle require manual coordination outside XRPL.
- XRPL currently provides no smart contracts or hooks—security research must focus on native ledger transactions and protocol primitives.

## Priority Risk Areas

- Liquidation logic: trigger unfair or blocked liquidations
- Interest rate calculations: incorrect accrual harming lenders or borrowers
- Clawback & deep-freeze primitives: bypass or disable asset controls
- Administrative state: inconsistencies between protocol records vs. actual funds
- Single Asset Vault (SAV):
  - Share mint/redeem and reward distribution correctness
  - Deposit/withdrawal edge cases and First Loss Capital handling
- Compliance primitives (permissioned domains, credentials): enforce access controls without loopholes

## Known Issues (Out of Reward Scope)

- `LoanBrokerCoverDeposit` submitted with only the base reserve returns `telFAILED_PROCESSING` — [XRPLF/rippled#5270](https://github.com/XRPLF/rippled/pull/5270) (10 Oct 2025)
- `VaultWithdraw` where the fee equals the withdrawal amount fails with `tecINVARIANT_FAILED` — [XRPLF/rippled#5876](https://github.com/XRPLF/rippled/pull/5876) (10 Oct 2025)
- `sign_for` multi-sign workflow can reject counterparty signatures as invalid — [XRPLF/rippled#5270](https://github.com/XRPLF/rippled/pull/5270) (10 Oct 2025)

## Impact Guidance

- **Critical (select when reporting):**
  - Drainage or theft of funds from vault objects or First Loss Capital reserves
  - Direct loss of funds to any participant
  - Manipulation of loan/vault settings that unfairly redistributes funds or lets attackers game protocol economics (including multi-token interactions such as IOUs/MPTs)
- **High:**
  - Unauthorized modification of protocol fees (late, repayment, management, etc.)
  - Permanent freezing of user funds or unclaimed yield where recovery requires a hardfork or equivalent extraordinary action
  - Theft or permanent freezing of unclaimed yield balances
- **Medium:** Layer 0/1/2 bugs causing unintended primitive behavior without concrete funds at risk
- **Low:** Griefing or denial scenarios with no economic damage to any user
- **Insights:** Security best practices, optimizations, architectural or documentation improvements (choose only if no other impact applies)

## Out-of-Scope Impacts

- Incorrect data supplied by external oracles (unless the bug directly causes the bad data)
- Economic or governance attacks such as 51% attacks, liquidity shortages, or Sybil vectors
- Issues requiring leaked keys, privileged addresses, or impacts reliant on centralization assumptions alone
- Stablecoin depegs not caused by a protocol bug, or mentions of secrets/credentials without proof of production use
- Impacts already exploited by the reporter to cause damage, or those depending on deactivated/privileged accounts without code changes
- Best-practice recommendations, feature requests, test/config-only issues, or self-inflicted impacts by reporters

## Reward Rules & Terms

- Rewards distributed per Immunefi Standardized Competition Terms (All Star & Podium pools apply)
- All Star and Podium pools are reserved for Immunefi All Star Program participants
- Private known issues count if not publicly disclosed
- Duplicate bug submissions valid; duplicate insights invalid
- All findings kept private until program end
- Insight contributions receive a designated portion of the overall reward pool when accompanied by runnable PoCs

## Governance & Reporting

- Insight severity recognizes contributions beyond immediate vulnerabilities; reports must include runnable PoCs and are rewarded under Immunefi’s Standardized Competition Terms (duplicate insight submissions are not eligible).
- Immunefi adjudicates any dispute between Ripple/XRPL and researchers on report validity or severity.
- Asset accuracy assurance: bugs on assets mistakenly listed in-scope remain reward-eligible.
- Private known issues that were not publicly disclosed qualify for the unlocked pool.
- Ripple/XRPL follows Primacy of Rules—the public program terms take precedence over impact narratives.
- Responsible publication: whitehats may publish after a fix/payout or invalidation; reports in mediation stay private. Immunefi may publish the leaderboard and findings summary.
- Ripple/XRPL meets Immunefi Standard Badge requirements for program hygiene and transparency.

## KYC & Payout Requirements

- KYC is mandatory for all payouts and is processed by Immunefi’s partner Onfido.
- Researchers must supply proof of address (e.g., redacted bank statement or recent utility bill) and a passport or other government-issued ID.
- Requested KYC documentation must be submitted within 14 days or rewards may be forfeited; Immunefi can grant exceptions in extenuating circumstances.

## Prohibited Activities

- Testing on mainnet or public testnet deployments; use sanctioned local environments instead
- Interacting with pricing oracles, third-party smart contracts, or non-scope integrations
- Phishing or other social engineering targeting Ripple/XRPL staff or users
- Testing that involves third-party systems (e.g., browser extensions, SSO providers, ad networks) outside the provided scope
- Denial-of-service attacks or automated testing that generates excessive traffic against project assets
- Public disclosure of unpatched or embargoed vulnerabilities before program conclusion
- Any other behavior disallowed under the Immunefi Rules

## Feasibility Standards

- Immunefi’s feasibility limitation standards govern how severity arguments may cite practical obstacles.
- Severity is not downgraded solely because an exploit would require chain rollbacks, pre-impact bug monitoring, or notable attack investment.
- Security researchers should not rely on the attacker’s assumed financial risk or similar external mitigations to argue for lower impact.
- Consult the Immunefi “When Is an Impactful Attack Downgraded” guidance when discussing feasibility.

## Testing & Environment Constraints

- Proof of concept deliverables are required for every severity; default runnable PoC expectation is **Option B: stand-alone node + transactions**  
  1. Launch a local node (`./rippled -a --start --conf rippled.cfg`).  
  2. Drive the scenario purely via JSON-RPC (e.g., create vault/broker/loan, submit transactions).  
  3. Demonstrate the invariant break directly in ledger state (`ledger_entry`, `account_lines`, etc.).  
  Unit-test PoCs are acceptable only if they also submit real transactions (no direct ledger mutation).
- Allowed testnet: `lend.devnet.rippletest.net`; faucet `https://lend-faucet.devnet.rippletest.net/accounts`
- Follow XRPL faucet usage docs (`https://xrpl.org/resources/dev-tools/xrp-faucets`)
- Reference the Immunefi Proof of Concept Guidelines & Rules when packaging PoCs
- No testing on mainnet or public testnet code, no external smart contracts/oracles, no DoS or social engineering
- Automated testing must not generate excessive traffic

## Resources

- Build instructions: `BUILD.md` or `https://github.com/XRPLF/rippled/blob/develop/BUILD.md`
- Prior audits: Ripple public reports (`http://opensource.ripple.com`), Single Asset Vault audit (Halborn, 27 Jun 2025)
- Ripple audit archive: SAV, MPT, Credentials, and Permissioned Domains reports at `http://opensource.ripple.com` (unfixed issues cited there are not reward-eligible)
- General XRPL information: `https://xrpl.org/`
- Immunefi resource hub: `https://immunefi.com/audit-competition/xrpl-ripple/resources`
- XRPL documentation & standards: `https://xrpl.org/docs`, `https://github.com/XRPLF/XRPL-Standards`
- Rippled codebase: `https://github.com/XRPLF/rippled`
- Dev tooling & explorers: `https://devnet.xrpl.org/`, `https://xrpl.org/resources/dev-tools/xrp-faucets`
- Learning & sample code: `https://learn.xrpl.org/`, `https://github.com/XRPLF/xrpl-dev-portal`, `https://github.com/XRPLF/xrpl-dev-portal/tree/master/_code-samples`
- Contribution & network references: `https://xrpl.org/resources/contribute-code`, `https://xrpl.org/known-amendments`
- Key XLS specs: XLS-66d (Lending Protocol), XLS-65d (Single Asset Vault), XLS-33 (MPT), XLS-80 (Permissioned Domains), XLS-70 (Credentials), XLS-77 (Deep-freeze) via XRPL Standards discussions and open documentation (XRPL Standards + opensource.ripple.com)
