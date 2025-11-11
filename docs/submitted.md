# Submitted XRPL Lending Protocol Findings

Last updated: 2025-11-09

This index tracks every Attackathon submission so the corresponding reports are easy to locate while the triage process is in flight.

> **Submission cooldown:** A fresh report went in today, so the next Immunefi submission window opens 24 hours after the latest ticket.

## Critical

### Report 57997 — Minimum-cover rounding in `LoanBrokerCoverWithdraw`
- Status: Escalated (Chief Finding)
- Impact: Under-collateralized first-loss capital withdrawal and direct fund loss
- Key components: `LoanBrokerCoverWithdraw::preclaim`, `roundToAsset`, `Number` normalization
- Local reference: `reports/submitted/critical/report-57997-loanbrokercov-min-cover-rounding/report.md`
- Supporting: `reports/submitted/critical/report-57997-loanbrokercov-min-cover-rounding/status.md`, `reports/submitted/critical/report-57997-loanbrokercov-min-cover-rounding/reviewer_reply.md`

### Report 59012 — LoanManage grace-window overflow drains First Loss Capital
- Status: Reported (Critical)
- Impact: Broker defaults healthy loan immediately and seizes `sfCoverAvailable`
- Key components: `LoanManage::preclaim`, `hasExpired`, `LoanManage::defaultLoan`
- Local reference: `reports/submitted/critical/report-59012-loanmanage-grace-overflow/report.md`

### Report — Frozen `LoanBrokerDelete` payout drains first-loss capital despite issuer freeze
- Status: Reported (Critical)
- Impact: Frozen broker owner drains `sfCoverAvailable` when deleting the broker
- Key components: `LoanBrokerDelete::preclaim`, `LoanBrokerDelete::doApply`, `accountSend`
- Local reference: `reports/submitted/critical/loanbrokerdelete-freeze-bypass/report.md`

### Report — `LoanBrokerCoverWithdraw` pays frozen destinations
- Status: Reported (Critical)
- Impact: Frozen accounts siphon first-loss capital via cover withdrawals
- Key components: `LoanBrokerCoverWithdraw::preclaim`, `LoanBrokerCoverWithdraw::doApply`, `accountSend`
- Local reference: `reports/submitted/critical/loanbrokercovwithdraw-freeze-destination/report.md`

### Report — `LoanSet` origination fees bypass issuer freeze
- Status: Reported (Critical)
- Impact: Frozen broker owner still receives origination fees on new loans
- Key components: `LoanSet::preclaim`, `LoanSet::doApply`, `accountSendMulti`
- Local reference: `reports/submitted/critical/loanset-origination-fees-freeze-bypass/report.md`

### Report — `LoanManage::unimpairLoan` next-due overflow enables immediate defaults
- Status: Submitted (Critical)
- Impact: Overflowed due date allows instant default and drains first-loss capital
- Key components: `LoanManage::unimpairLoan`, `hasExpired`, `LoanManage::defaultLoan`
- Local reference: `reports/drafts/medium/loanmanage-unimpair-next-due-overflow.md`

## High

### Report 58178 — LoanPay fee routing below minimum cover
- Status: Escalated (Chief Finding)
- Impact: Broker siphons first-loss capital by misrouting fees when cover is already deficient
- Key components: `LoanPay::doApply`, `roundToAsset`, lending cover helpers
- Local reference: `reports/submitted/high/report-58178-loanpay-fee-routing/submission.md`
- Additional: `reports/submitted/high/report-58178-loanpay-fee-routing/resubmission.md` (Closed duplicate triage)

### Report 58315 — LoanSet borrower reserve bypass
- Status: Escalated (Chief Finding)
- Impact: Unlimited broker-originated loans despite borrower failing XRP reserve requirement
- Key components: `LoanSet::doApply`, `Transactor::apply` (`mPriorBalance` handling)
- Local reference: `reports/submitted/high/report-58315-loanset-borrower-reserve-bypass/report.md`

### Report 58441 — LoanPay ignores issuer freeze when routing broker fees
- Status: Escalated (Chief Finding)
- Impact: Frozen broker owners siphon fees, draining first-loss capital
- Key components: `LoanPay::doApply`, `checkFrozen`, `accountSendMulti`
- Local reference: `reports/submitted/high/report-58441-loanpay-fee-freeze-bypass/report.md`

## Drafts

### Loan default cover return ignores issuer freeze on vault pseudo-account
- Status: Draft (Medium)
- Local reference: `reports/drafts/medium/loan-default-cover-freeze-bypass.md`


