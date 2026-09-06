# AI safety architecture

## Result contract

Every material result records provider/model, model version, prompt/template version, schema version, inputs, evidence references, confidence, source quality, concise rationale, limitations, human-review requirement, cost, latency, and subsequent human decision. Private hidden reasoning is neither requested nor stored.

## Provider gate

The provider router checks organization approval, permitted purpose, data categories, region, retention/training settings, and contract status before a request. If no provider satisfies policy, the job fails closed. Models receive minimized inputs through narrow tools; no model receives unrestricted database, filesystem, communications, payment, or portal access.

## Change management

Model changes progress through development, staging, then production after evaluation-set comparison for precision, recall, false positives/negatives, structured-output reliability, latency, and cost. Material regressions block promotion. See `PRODUCT_SAFETY_RULES.md` and `AI_RISK_REGISTER.md`.
