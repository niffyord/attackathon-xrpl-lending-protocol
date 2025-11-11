# Submitted Findings Directory

This directory gathers every confirmed Attackathon submission so the latest report versions stay in one place while triage is still active.

## Layout

- `critical/` — escalated or reported critical-impact issues. Each report sits in its own folder named `<slug>/` or `report-<id>-<slug>/` and contains a `report.md`. Supplemental material (for example `status.md`, `reviewer_reply.md`) lives alongside the primary report.
- `high/` — escalated or reported high-severity findings, organised the same way. When a finding has multiple triage threads (for example resubmission after a closure), the extra write-ups live alongside the main `report.md`.

## Drafts

Draft reports that still need polish or triage belong under `../drafts/`. Each draft file is named after the scenario it covers so it is easy to map to screenshots and planning notes.

## Updating

When another submission is confirmed, create a new folder under the appropriate severity and drop the final write-up in as `report.md`. Add any supporting notes you want to track (status updates, reviewer replies, PoC commands) as additional files inside the same folder, and remember to refresh `../../SUBMITTED_ISSUES.md` with the new path.

