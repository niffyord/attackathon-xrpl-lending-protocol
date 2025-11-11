## Environment & Build
- Host: local Ubuntu-on-WSL session (same repo path `/mnt/c/Users/mac/Desktop/imm/attackathon-xrpl-lending-protocol`)
- Toolchain: Conan/CMake per `BUILD.md`; invoked `cmake --build .build --target rippled -j8`
- Fixes applied during build: updated `src/test/app/Loan_test.cpp` to use `PrettyAmount.value().xrp()` so the test target compiles with the current `PrettyAmount` API
- Binary location: `.build/rippled`

## Runtime Configuration
- Copied defaults from `rippled.dev.cfg` and added:
  - `[port_rpc_admin_local] admin = 127.0.0.1` (enables local admin JSON-RPC)
  - `[features]` list includes `SingleAssetVault`, `LendingProtocol`, `Batch`, `Credentials`, `PermissionedDomains`, `MPTokensV1`
- Run mode: `./.build/rippled --conf rippled.dev.cfg --standalone`
- Admin endpoint: `http://127.0.0.1:5005`

## Ledger Initialization
1. Deterministic accounts generated via `wallet_propose` with passphrases:
   - Issuer `rE1Axr8SgFvRCfCi3pESQp9RLcAh2LnGw3`
   - Broker owner `rBrRBZNanp2SFgaGdoFWxsff8tQUMCWPCD`
   - Borrower `rfhAdJDiKVnXtXZMktMZYhPVywLj8WouNc`
2. Funded each from genesis master (`snoPBrXtMeMyMHUVTgbuqAfg1SUTb`) using `Payment` txs, sealing ledgers with `ledger_accept`
3. Broker trustline to issuer IOU (`USD`) created; issuer Payment sends `1.5e15` IOU
4. Enabled issuer `lsfDefaultRipple` via `AccountSet` to satisfy `VaultCreate::canAddHolding`

## Vault & Loan Broker Setup
1. `VaultCreate` with `{Account: broker, Asset: issuer/USD, Scale:12}` → success (`hash D8D2D8C9DCF...`)
2. Extracted `VaultID` `6C5E6A90...` from metadata via `tx` RPC
3. `LoanBrokerSet` pointing to vault, `CoverRateMinimum=1` → success (`hash C0CF8899...`)
4. `LoanBrokerCoverDeposit` added `1000000000000200` issuer/USD to cover pool (`hash 4F3597DE...`)

## P0C Progress
- Steps 1–11 of `report.md` re-run on fresh ledger (post `[signing_support]=true`): deterministic funding, trust, IOU issuance, `VaultCreate`, `LoanBrokerSet`, and `LoanBrokerCoverDeposit` now repeatable; new hashes logged (e.g., `VaultCreate` -> `5C2599F1…`, `LoanBrokerSet` -> `52FF197C…`, `LoanBrokerID` = `AE252692…`)
- Reviewer error (“Invalid field tx_json.Amount”) resolved earlier by respecting 16-digit IOU precision; commands in section above still valid
- Current blockers:
  1. **Vault is unfunded**: `VaultDeposit` attempts either drain the issuer/broker IOU balance (`tecINSUFFICIENT_FUNDS`) or violate invariants (deposit amount exceeds available IOUs). Need to move `issuer/USD` back into broker account and deposit into vault until `sfAssetsAvailable` reflects the large principal
  2. **Counterparty signature on inner LoanSet**: even after enabling signing support, `sign`/`sign_for` with `signature_target:CounterpartySignature` returns `error_code 73`. Working plan is to reuse the borrower-signed transaction (with Sequence=1, Fee=200) from `loan_borrower_signed.json`, embed that `CounterpartySignature` into the inner tx, and rely on `LoanSet` logic (it accepts borrower counter-signature even if the borrower initiated tx). Need to re-run `sign` pipeline once vault funding is solved
- After those blockers are cleared:
  - Rebuild Batch JSON (outer `tfIndependent`, `Fee=30`, inner Sequences `brokerSeq+1/2`)
  - Submit `Batch` → expect `tesSUCCESS`
  - Continue with ledger dumps (steps 13–15) to capture `CoverAvailable`, `DebtTotal`, and withdraw slack

## Next Actions
1. Keep seeding the vault with issuer IOUs (`VaultDeposit` from `rE1Axr8…`) in increments the trustline accepts (≤10⁹ per tx). Close the ledger between deposits and monitor `AssetsAvailable` on `VaultID FD099E…` until it reaches the ~10¹⁵ level needed to reproduce the rounding bug.
2. Once vault funding is sufficient, reuse `loan_borrower_signed.json` to populate `loan_inner_seq.json`:
   - Copy the borrower-signed fields (`CounterpartySignature`, `TxnSignature`, `SigningPubKey`), reset `Fee` to `"0"`, set `Flags |= tfInnerBatchTxn`, `Sequence = BROKER_SEQ + 1`, and ensure the filler Payment uses `Sequence = BROKER_SEQ + 2`.
3. Rebuild `batch_submit.json` with `Flags = tfIndependent`, `Fee = 30`, `RawTransactions = [signed LoanSet, filler Payment]`. Submit, `ledger_accept`, then:
   - Record Batch `engine_result` / hash
   - Run `ledger_entry` on `LoanBrokerID AE252692…` before/after `LoanBrokerCoverWithdraw (400000 IOU)`
   - Compute `CoverAvailable * 100000 / DebtTotal` to show it falls below `CoverRateMinimum = 1`
4. Document the JSON-RPC responses and ratios as the “expected outputs” package for the reviewer once the Batch + withdraw sequence completes.***
