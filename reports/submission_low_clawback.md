# Title
Clawback amount rounding can slightly undercut the required minimum cover

# Description

## Brief/Intro
`LoanBrokerCoverClawback::determineClawAmount` converts the permitted clawback (`maxClawAmount`) into an `STAmount` without explicitly rounding downward. The conversion uses STAmount’s canonicalisation, which rounds to the nearest representable value based on the vault asset’s precision. When `maxClawAmount` sits between representable quanta, the result may round up slightly, allowing the issuer to claw back marginally more first-loss capital than policy allows. The deviation is at most one rounding unit, so severity is low, but it violates the invariant that cover never falls below the computed floor.

## Vulnerability Details
- Clawback logic:
  ```cpp
  auto const maxClawAmount = sleBroker[sfCoverAvailable] -
      tenthBipsOfValue(sleBroker[sfDebtTotal], TenthBips32(sleBroker[sfCoverRateMinimum]));
  ...
  return STAmount{vaultAsset, maxClawAmount};
  ```
  (`src/xrpld/app/tx/detail/LoanBrokerCoverClawback.cpp:138-165`)

- `maxClawAmount` is a `Number`. Constructing `STAmount{vaultAsset, maxClawAmount}` triggers canonicalisation (`src/libxrpl/protocol/STAmount.cpp:873`), which rounds to the nearest representable value (ties to even) when the mantissa exceeds the asset precision.

- If the true allowed clawback is, for example, `5.0000045` units and the asset precision is 6 decimals, canonicalisation can round up to `5.000005`, clawing an extra `0.0000005`. This pushes cover below the computed minimum by the same delta.

- The code comments note the precision mismatch but do not enforce downward rounding, so the slight invariant breach remains possible.

## Impact Details
- Impact is bounded by the vault asset’s minimum increment (≤1 unit of the rounding quantum), hence low severity.
- Still, it breaks the expectation that issuers cannot reduce cover below the calculated minimum during clawback.

## References
- `src/xrpld/app/tx/detail/LoanBrokerCoverClawback.cpp:138-165`
- `src/libxrpl/protocol/STAmount.cpp:873-942` (canonicalisation and rounding direction)
- `docs/validated_findings.md` (Low – Clawback Rounding section)

# Proof of Concept
1. Set up a broker/vault environment where `sfCoverAvailable - minimumCover` equals half the asset quantum (e.g., 0.0000005).
2. Execute `LoanBrokerCoverClawback` specifying zero amount (meaning “claw to minimum”).
3. Inspect `sfCoverAvailable` afterwards and note it has fallen slightly below the expected minimum.
4. Demonstrate the delta equals the asset’s rounding step, confirming over-clawback occurred.
