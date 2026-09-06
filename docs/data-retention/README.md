# Data retention

Retention is category- and organization-configurable. Example defaults are product hypotheses, not declarations of legal sufficiency.

| Category | Illustrative default | Notes |
| --- | ---: | --- |
| Raw teardown video | 30 days | Short-lived; retain selected evidence separately |
| Selected evidence | Organization policy | May be subject to contractual need or hold |
| AI intermediate artifacts | 7 days | Delete when no longer required for reproducibility |
| Repair records | Organization policy | Counsel must set jurisdictional baseline |
| Audit events | Organization policy | Append-oriented and potentially longer-lived |
| Customer-identifying data | Minimum necessary | Prefer pseudonymization |

Deletion workers must verify tenant, policy, retention hold, source/derivative relationship, and audit the outcome. Backups need a documented expiry model so deletion propagates rather than promising immediate physical erasure where it cannot be guaranteed.
