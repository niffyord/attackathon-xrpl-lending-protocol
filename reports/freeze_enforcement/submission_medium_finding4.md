# Title
Loan default cover return ignores issuer freeze on vault pseudo‑account (deep/normal), credits frozen receiver

# Description

## Brief/Intro
`LoanManage` in the `tfLoanDefault` path transfers First‑Loss Capital from the broker pseudo‑account back to the vault pseudo‑account using `accountSend` without enforcing `checkFrozen`/`checkDeepFrozen` on the receiver. If the issuer has frozen the vault pseudo‑account’s trust line (IOU) or the asset is otherwise locked (MPT), the transfer still succeeds. This violates freeze semantics and credits funds to a frozen receiver.

Note: This is a policy/compliance violation; the credited value remains inside the vault structure (receiver is the vault pseudo‑account), i.e., this path does not directly drain funds to an external account.

## Vulnerability Details
- `LoanManage::preclaim` validates flags/timing, but does not gate the broker/vault pseudo‑accounts with freeze checks.
- `LoanManage::defaultLoan` unconditionally executes:
  ```cpp
  return accountSend(
      view,
      brokerSle->at(sfAccount),
      vaultSle->at(sfAccount),
      STAmount{vaultAsset, defaultCovered},
      j,
      WaiveTransferFee::Yes);
  ```
  (src/xrpld/app/tx/detail/LoanManage.cpp:292–296)
- The underlying send/credit paths (`accountSend` → `rippleCreditIOU`/`rippleCreditMPT`) do not enforce freeze; callers must pre‑validate. In this path they don’t, so a frozen receiver is still credited.

## Impact Details
- Impact category (Medium): “A bug in layer 0/1/2 code that results in unintended primitive behavior with no concrete funds at direct risk.”
- Effects: issuer freeze and policy controls are bypassed on default settlement; funds credited to frozen vault pseudo‑account, violating compliance constraints.

## References
- Default transfer: src/xrpld/app/tx/detail/LoanManage.cpp:292–296
- Freeze checks interface: include/xrpl/ledger/View.h (checkFrozen/checkDeepFrozen)
- Send/credit internals: src/libxrpl/ledger/View.cpp (IOU/MPT rippleCredit*)

# Proof of Concept

> Run against a local devnet/single‑node. Commands mirror other freeze‑enforcement PoCs and use jq for parsing.

1. Start node
   ```bash
   ./rippled -a --start --conf rippled.cfg
   ```

2. Derive wallets (issuer I, broker owner B, borrower R)
   ```bash
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"issuer default-freeze poc"}]}' | tee issuer_wallet.json
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"broker default-freeze poc"}]}' | tee broker_wallet.json
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"borrower default-freeze poc"}]}' | tee borrower_wallet.json

   ISSUER_ACCOUNT=$(jq -r '.result.account_id' issuer_wallet.json)
   ISSUER_SECRET=$(jq -r '.result.master_seed' issuer_wallet.json)
   BROKER_ACCOUNT=$(jq -r '.result.account_id' broker_wallet.json)
   BROKER_SECRET=$(jq -r '.result.master_seed' broker_wallet.json)
   BORROWER_ACCOUNT=$(jq -r '.result.account_id' borrower_wallet.json)
   BORROWER_SECRET=$(jq -r '.result.master_seed' borrower_wallet.json)
   ```

3. Fund accounts
   ```bash
   for acct in "$ISSUER_ACCOUNT" "$BROKER_ACCOUNT" "$BORROWER_ACCOUNT"; do
     curl -s -X POST http://127.0.0.1:5005 -d "{\
       \"method\":\"submit\",\
       \"params\":[{\
         \"secret\":\"snoPBrXtMeMyMHUVTgbuqAfg1SUTb\",\
         \"tx_json\":{\
           \"TransactionType\":\"Payment\",\
           \"Account\":\"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh\",\
           \"Destination\":\"$acct\",\
           \"Amount\":\"100000000000\"\
         }\
       }]\
     }" | jq '.result.engine_result'
   done
   ```

4. Establish IOU trustlines and fund owner
   ```bash
   # Broker trust line to issuer IOU
   curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"submit\",\
     \"params\":[{\
       \"secret\":\"$BROKER_SECRET\",\
       \"tx_json\":{\
         \"TransactionType\":\"TrustSet\",\
         \"Account\":\"$BROKER_ACCOUNT\",\
         \"LimitAmount\":{\
           \"currency\":\"USD\",\
           \"issuer\":\"$ISSUER_ACCOUNT\",\
           \"value\":\"1000000000000\"\
         },\
         \"Flags\":262144\
       }\
     }]\
   }" | jq '.result.engine_result'

   # Borrower trust line (LoanSet later)
   curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"submit\",\
     \"params\":[{\
       \"secret\":\"$BORROWER_SECRET\",\
       \"tx_json\":{\
         \"TransactionType\":\"TrustSet\",\
         \"Account\":\"$BORROWER_ACCOUNT\",\
         \"LimitAmount\":{\
           \"currency\":\"USD\",\
           \"issuer\":\"$ISSUER_ACCOUNT\",\
           \"value\":\"1000000000000\"\
         }\
       }\
     }]\
   }" | jq '.result.engine_result'

   # Issuer supplies IOUs to broker owner
   curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"submit\",\
     \"params\":[{\
       \"secret\":\"$ISSUER_SECRET\",\
       \"tx_json\":{\
         \"TransactionType\":\"Payment\",\
         \"Account\":\"$ISSUER_ACCOUNT\",\
         \"Destination\":\"$BROKER_ACCOUNT\",\
         \"Amount\":{\
           \"currency\":\"USD\",\
           \"issuer\":\"$ISSUER_ACCOUNT\",\
           \"value\":\"5000000\"\
         },\
         \"Flags\":131072\
       }\
     }]\
   }" | jq '.result.engine_result'
   ```

5. Create vault and get `VaultID`
   ```bash
   VAULT_HASH=$(curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"submit\",\
     \"params\":[{\
       \"secret\":\"$BROKER_SECRET\",\
       \"tx_json\":{\
         \"TransactionType\":\"VaultCreate\",\
         \"Account\":\"$BROKER_ACCOUNT\",\
         \"Asset\":{\
           \"currency\":\"USD\",\
           \"issuer\":\"$ISSUER_ACCOUNT\"\
         },\
         \"Scale\":6\
       }\
     }]\
   }" | jq -r '.result.tx_json.hash')

   VAULT_ID=$(curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"tx\",\
     \"params\":[{\"transaction\":\"$VAULT_HASH\"}]\
   }" | jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Vault").CreatedNode.LedgerIndex')
   ```

6. Create LoanBroker and deposit cover
   ```bash
   BROKER_HASH=$(curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"submit\",\
     \"params\":[{\
       \"secret\":\"$BROKER_SECRET\",\
       \"tx_json\":{\
         \"TransactionType\":\"LoanBrokerSet\",\
         \"Account\":\"$BROKER_ACCOUNT\",\
         \"VaultID\":\"$VAULT_ID\",\
         \"CoverRateMinimum\":1\
       }\
     }]\
   }" | jq -r '.result.tx_json.hash')

   LOANBROKER_ID=$(curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"tx\",\
     \"params\":[{\"transaction\":\"$BROKER_HASH\"}]\
   }" | jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="LoanBroker").CreatedNode.LedgerIndex')

   curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"submit\",\
     \"params\":[{\
       \"secret\":\"$BROKER_SECRET\",\
       \"tx_json\":{\
         \"TransactionType\":\"LoanBrokerCoverDeposit\",\
         \"Account\":\"$BROKER_ACCOUNT\",\
         \"LoanBrokerID\":\"$LOANBROKER_ID\",\
         \"Amount\":{\
           \"currency\":\"USD\",\
           \"issuer\":\"$ISSUER_ACCOUNT\",\
           \"value\":\"1000000\"\
         }\
       }\
     }]\
   }" | jq '.result.engine_result'
   ```

7. Get vault pseudo‑account and freeze it (issuer‑side freeze)
   ```bash
   VAULT_PSEUDO=$(curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"vault_info\",\
     \"params\":[{\"vault_id\":\"$VAULT_ID\"}]\
   }" | jq -r '.result.vault.Account')

   # Issuer freezes the trust line to the vault pseudo‑account
   curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"submit\",\
     \"params\":[{\
       \"secret\":\"$ISSUER_SECRET\",\
       \"tx_json\":{\
         \"TransactionType\":\"TrustSet\",\
         \"Account\":\"$ISSUER_ACCOUNT\",\
         \"LimitAmount\":{\
           \"currency\":\"USD\",\
           \"issuer\":\"$VAULT_PSEUDO\",\
           \"value\":\"0\"\
         },\
         \"Flags\":1048576\
       }\
     }]\
   }" | jq '.result.engine_result'

   # Confirm freeze flag on the pseudo‑account trust line
   curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"account_lines\",\
     \"params\":[{\
       \"account\":\"$VAULT_PSEUDO\",\
       \"peer\":\"$ISSUER_ACCOUNT\"\
     }]\
   }" | jq '.result.lines[0].freeze'
   ```

8. Create a small‑interval loan (Batch recommended) and let it lapse
   ```bash
   # Prepare a Batch with a LoanSet inner transaction:
   #  - LoanBrokerID = $LOANBROKER_ID
   #  - PrincipalRequested ~ 1000 (USD IOU)
   #  - PaymentInterval = 1, GracePeriod = 0
   #  - Counterparty + CounterpartySignature as required by LoanSet
   # Sign inner txs offline (rippled sign --offline / sign_for), then submit Batch:
   #   RawTransactions: [ {RawTransaction: $INNER_LOAN_BLOB}, {RawTransaction: $FILLER_BLOB} ]

   # After Batch succeeds, extract LOAN_ID from tx meta (CreatedNode of type "Loan").
   # Wait a couple of seconds to ensure next due date has passed:
   sleep 3
   ```

9. Default the loan; observe transfer to frozen receiver succeeds
   ```bash
   curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"submit\",\
     \"params\":[{\
       \"secret\":\"$BROKER_SECRET\",\
       \"tx_json\":{\
         \"TransactionType\":\"LoanManage\",\
         \"Account\":\"$BROKER_ACCOUNT\",\
         \"LoanID\":\"$LOAN_ID\",\
         \"Flags\":65536   # tfLoanDefault\
       }\
     }]\
   }" | jq '.result.engine_result'
   ```

10. Verify the frozen receiver was credited
    ```bash
    # Pseudo‑account trust line balance increased despite issuer freeze
    curl -s -X POST http://127.0.0.1:5005 -d "{\
      \"method\":\"account_lines\",\
      \"params\":[{\
        \"account\":\"$VAULT_PSEUDO\",\
        \"peer\":\"$ISSUER_ACCOUNT\"\
      }]\
    }" | jq '.result.lines[0].balance'

    # Vault object reflects defaultCovered credited to AssetsAvailable
    curl -s -X POST http://127.0.0.1:5005 -d "{\
      \"method\":\"vault_info\",\
      \"params\":[{\"vault_id\":\"$VAULT_ID\"}]\
    }" | jq '.result.vault | {AssetsAvailable:."AssetsAvailable", AssetsTotal:."AssetsTotal"}'
    ```

**Expected:** The default should be rejected if the receiver is frozen.

**Actual:** The transfer completes and the frozen pseudo‑account receives funds.

11. Confirm freeze flag remains set (policy bypass, not a state change)
    ```bash
    curl -s -X POST http://127.0.0.1:5005 -d "{\
      \"method\":\"account_lines\",\
      \"params\":[{\
        \"account\":\"$VAULT_PSEUDO\",\
        \"peer\":\"$ISSUER_ACCOUNT\"\
      }]\
    }" | jq '.result.lines[0].freeze'
    ```
    The value remains `true`, showing the issuer freeze was not lifted; the transfer bypassed policy rather than changing freeze state.

## Recommended Mitigation

- Enforce freeze at admission for the default path:
  - In `LoanManage::preclaim`, after loading `loanBrokerSle` and `vaultSle`, add:
    - `if (auto ret = checkFrozen(ctx.view, loanBrokerSle->at(sfAccount), vaultSle->at(sfAsset))) return ret;`
    - `if (auto ret = checkDeepFrozen(ctx.view, vaultSle->at(sfAccount), vaultSle->at(sfAsset))) return ret;`
  - This mirrors other lending flows (LoanPay, VaultDeposit/Withdraw, CoverDeposit/Withdraw).
- Add a defensive guard in `LoanManage::defaultLoan` before `accountSend` to re‑check the receiver with `checkDeepFrozen` and the sender with `checkFrozen` to avoid TOCTOU across complex updates.
- Consider a small helper (e.g., `enforceFreezeForTransfer(view, from, to, asset)`) to centralize this pattern and reuse it in similar state‑transition sends.
