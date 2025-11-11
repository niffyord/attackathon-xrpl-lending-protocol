# Single Asset Vault Share Accounting Asymmetry

## Summary
Deposits into a Single Asset Vault (SAV) mint shares based on the vault's **gross** assets, ignoring `sfLossUnrealized`. In contrast, withdrawals and clawbacks redeem shares against **net** assets (`AssetsTotal - LossUnrealized`). This inconsistency lets an attacker impair a self-controlled loan to inflate `LossUnrealized`, then accept victim deposits priced too high. The attacker can later withdraw using their pre-existing shares at correct net asset valuation, extracting the spread and leaving new depositors under-collateralized.

## Impact
Existing shareholders can profit by marking their own debt as impaired before victims deposit, yielding more redeemable value than the attacker contributed. Victim shares become worth less than their deposit, enabling value siphoning without immediate ledger violation.

## Affected Components
- `src/xrpld/app/tx/detail/VaultDeposit.cpp`
- `src/xrpld/app/tx/detail/VaultWithdraw.cpp`
- `src/xrpld/app/tx/detail/VaultClawback.cpp`
- Vault math helpers in `src/xrpld/app/misc/detail`
- SAV share math in `src/libxrpl`

## Recommended Fix Direction
Align the share conversion logic across deposit, withdraw, and clawback paths so all operations consistently use net asset valuation. Consider pricing deposits using net assets or adjusting redemption paths accordingly, ensuring new shares are fully collateralized even when `sfLossUnrealized` is non-zero.
