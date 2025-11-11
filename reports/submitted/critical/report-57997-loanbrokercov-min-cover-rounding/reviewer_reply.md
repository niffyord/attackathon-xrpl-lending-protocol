## Reviewer Reply – Submission “Critical: Minimum-cover rounding…”

Hi Vito,

Thanks for the follow-up. The `invalidParams` error in your snippet is due to XRPL’s IOU precision limit: `STAmount` supports at most 16 significant digits. The payment you tested (`value = 1500000000000000000000000`, 25 digits) cannot be represented, so the server rejects it.

Here’s the working command and response from the same deterministic accounts used in the PoC (issuer `rE1Axr8Sg…`, broker `rBrRBZN…`):

```bash
curl -s -X POST http://127.0.0.1:5005 -d '{
  "method":"submit",
  "params":[{
    "secret":"shsCsedVMq7cva4SZ3xksqs3uXwAv",
    "tx_json":{
      "TransactionType":"Payment",
      "Account":"rE1Axr8SgFvRCfCi3pESQp9RLcAh2LnGw3",
      "Destination":"rBrRBZNanp2SFgaGdoFWxsff8tQUMCWPCD",
      "Amount":{
        "currency":"USD",
        "issuer":"rE1Axr8SgFvRCfCi3pESQp9RLcAh2LnGw3",
        "value":"1500000000000000"
      },
      "Flags":131072
    }
  }]
}'
```

Response excerpt:

```
"engine_result": "tesSUCCESS",
"hash": "66EF67DB94950CC784CF4E840451B4EFD18AC158462A58D160D90E7D4EFBAB98"
```

This funds the broker pseudo-account with the high‑precision IOU needed for the PoC. We’re re-running the rest of the sequence (vault funding, Batch, withdrawal) on the refreshed devnet and will provide the full expected outputs once the vault assets match the scenario. But the payment step above is reproducible today and addresses the specific `invalidParams` error you hit.

Let me know if you need the full transaction blob or any other intermediary outputs.
