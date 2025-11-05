# Submitted XRPL Lending Protocol Findings

Last updated: 2025-11-02

This index tracks every Attackathon submission so the corresponding reports are easy to locate while the triage process is in flight.

## Critical

### Report 57997 — Minimum-cover rounding in `LoanBrokerCoverWithdraw`
- Status: Escalated (Chief Finding)
- Impact: Under-collateralized first-loss capital withdrawal and direct fund loss
- Key components: `LoanBrokerCoverWithdraw::preclaim`, `roundToAsset`, `Number` normalization
- Local reference: `reports/submitted/submission_critical.md`

### Pending — LoanBrokerDelete ignores issuer freeze during broker deletion
- Status: Draft (to submit)
- Impact: Frozen broker owner drains `sfCoverAvailable` when deleting the broker
- Key components: `LoanBrokerDelete::preclaim`, `LoanBrokerDelete::doApply`, `accountSend`
- Local reference: `reports/freeze_enforcement/submission_high_finding1.md`

### Pending — LoanBrokerCoverWithdraw pays frozen destinations
- Status: Draft (to submit)
- Impact: Frozen accounts siphon first-loss capital via cover withdrawals
- Key components: `LoanBrokerCoverWithdraw::preclaim`, `LoanBrokerCoverWithdraw::doApply`, `accountSend`
- Local reference: `reports/freeze_enforcement/submission_high_finding2.md`

### Pending — LoanSet origination fee bypasses issuer freeze
- Status: Draft (to submit)
- Impact: Frozen broker owner still receives origination fees on new loans
- Key components: `LoanSet::preclaim`, `LoanSet::doApply`, `accountSendMulti`
- Local reference: `reports/freeze_enforcement/submission_high_finding3.md`

## High

### Report 58178 — LoanPay fee routing below minimum cover
- Status: Reported (Chief Finding)
- Impact: Broker siphons first-loss capital by misrouting fees when cover is already deficient
- Key components: `LoanPay::doApply`, `roundToAsset`, lending cover helpers
- Local reference: `reports/submitted/submission_high_fee_routing.md`

### Report 58315 — LoanSet borrower reserve bypass
- Status: Reported (Chief Finding)
- Impact: Unlimited broker-originated loans despite borrower failing XRP reserve requirement
- Key components: `LoanSet::doApply`, `Transactor::apply` (`mPriorBalance` handling)
- Local reference: `reports/submitted/submission_high_reserve_bypass.md`

### Report 58441 — LoanPay ignores issuer freeze when routing broker fees
- Status: Reported (Chief Finding)
- Impact: Frozen broker owners siphon fees, draining first-loss capital
- Key components: `LoanPay::doApply`, `checkFrozen`, `accountSendMulti`
- Local reference: `reports/submitted/submission_high_fee_freeze.md`


