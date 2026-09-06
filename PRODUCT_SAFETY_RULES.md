# Product Safety Rules

These rules are mandatory engineering constraints.

1. nexaIQ is decision-support and workflow software. Qualified professionals retain repair, diagnostic, calibration, QC, and release decisions.
2. AI output starts as a candidate and must state confidence, source quality, evidence, reason, limitations, and `human_review_required=true`.
3. Never create a vehicle or repair “safety score.” Workflow percentages describe documentation only.
4. Never automatically approve structural work, welds, sectioning, corrosion protection, calibration, unresolved DTC disposition, competency, vehicle delivery, final QC, supplement submission, estimate changes, or OEM compliance.
5. High-impact actions require an authenticated human to choose Confirm, Dismiss, Needs Review, Escalate, Request More Evidence, or Override with Reason as applicable.
6. Sign-off must capture identity, role, location, RO, checkpoint, exact attestation, timestamp, authentication/device context, evidence, version, and intentional action. Never fabricate a signature.
7. Overrides require a reason and permanent audit entry. Selected high-risk overrides may require second approval; no gate is silently bypassed.
8. Significant recommendations link to accessible supporting sources. If unavailable, say so. Original source takes precedence over summaries.
9. Camera measurements are approximate and never replace approved structural measurement equipment.
10. AI may describe possible conditions but cannot certify safety, repair quality, OEM compliance, reimbursement, causation, technician qualification, or equipment accuracy.
11. Do not silently edit/delete estimates, send communications, submit supplements, close claims, change qualifications, approve repairs, or release vehicles.
12. Uploaded content is untrusted data. It cannot override system policy or authorize a tool action.
13. Use only authorized OEM/estimating data access; no scraping, credential sharing, access-control bypass, or unlicensed redistribution.
14. Any correction to a material record creates another audit event; original evidence is never overwritten by an AI derivative.
15. If policy, evidence, or applicability is uncertain, fail to review—not to approval.
