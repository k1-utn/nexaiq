# Incident response framework

This runbook must be adapted to actual vendors and reviewed for applicable notification duties before pilot.

1. **Detect and triage:** preserve relevant logs; assign severity; identify affected tenants, data classes, integrations, and time window.
2. **Contain:** revoke sessions/tokens, rotate exposed secrets, disable affected provider or integration, quarantine malicious uploads, and close access paths.
3. **Investigate:** establish facts without editing original evidence; record decisions and timeline in the incident system.
4. **Notification assessment:** engage privacy/security counsel to determine contractual, regulator, individual, insurer, or partner notice requirements and timing.
5. **Recover:** restore clean service, verify tenant isolation, monitor recurrence, and communicate approved status.
6. **Post-incident:** identify control failures, owners, deadlines, tests, and policy changes.

Covered playbooks: suspected leak, stolen credentials, cross-tenant access, compromised integration token, exposed media, malicious upload, and AI-provider incident. Never describe ordinary product audit logs as a validated forensic chain of custody.
