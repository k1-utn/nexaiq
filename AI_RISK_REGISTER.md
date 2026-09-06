# AI Risk Register

Status values: Open, Mitigated, Accepted by authorized owner, or Blocked. Acceptance never substitutes for legal/professional review.

| Risk | Severity | Likelihood | Mitigation | Owner | Status |
| --- | --- | --- | --- | --- | --- |
| Missed supplement candidate | High | Medium | Human teardown/estimate review; recall evaluation; “candidate” framing | AI Lead | Open |
| False-positive damage finding | High | Medium | Confidence/source quality, limitations, confirm/dismiss, no estimate write | AI Lead | Mitigated |
| UI implies physical safety approval | Critical | Medium | Prohibited language checks; no safety score; UX/legal review | Product + Legal | Mitigated |
| Unsupported OEM summary | Critical | Medium | Original-source-first, citation requirement, conflict escalation | OEM Data Owner | Open |
| Prompt injection in uploaded document | High | Medium | Treat content as data, narrow tools, deterministic parsing, isolated model context | Security | Mitigated |
| Cross-tenant AI input/output exposure | Critical | Low | Tenant context, RLS, scoped object paths, isolation tests, least privilege | Security | Open |
| Excess personal information sent to AI | High | Medium | Data minimization, redaction, provider/purpose policy gate | Privacy Officer | Open |
| Provider uses data contrary to policy | High | Low | Contract/DPA/training/retention registry; fail-closed router | Vendor Risk | Open |
| Model change causes quality regression | High | Medium | Version pinning, staging, evaluation gate, rollback | AI Lead | Open |
| Hidden autonomous high-impact action | Critical | Low | Candidate-only tools, explicit human command boundary, audit events | Engineering | Mitigated |
| Confidence presented as certainty | High | Medium | Calibrated label plus source/limitations; content QA | Product | Mitigated |
| Camera interpreted as structural measurement | Critical | Medium | Approximation disclaimer; approved-equipment data requested | Product | Mitigated |
| Inaccurate estimate parse | High | Medium | Preserve original/hash, deterministic confidence, line-by-line human verification | Estimating Lead | Open |
| Evidence derivative overwrites original | Critical | Low | Separate immutable source metadata/object; derivatives linked by parent | Engineering | Mitigated |
| Unsupported causation/defamation | High | Low | “Possible previous-repair indicators”; human/insurer causation decision | Product + Legal | Mitigated |
| Cost runaway or video over-processing | Medium | Medium | Frame selection, budgets, per-job cost, quotas, provider limit | Platform | Open |
| Private reasoning or sensitive text logged | High | Low | Store structured rationale only; log redaction | Security | Open |
