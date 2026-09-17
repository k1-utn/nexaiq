import { z } from "zod";

export const humanDecisionSchema = z.enum([
  "pending_review",
  "confirmed",
  "dismissed",
  "needs_review",
  "escalated",
  "more_evidence_requested",
]);

export const loginCredentialsSchema = z.object({
  email: z.email().trim().toLowerCase(),
  password: z.string().min(1).max(1024),
});

export const aiResultSchema = z.object({
  findingType: z.string().min(1),
  confidence: z.number().min(0).max(1),
  sourceQuality: z.enum(["source_document", "camera_only", "mixed", "unknown"]),
  humanReviewRequired: z.literal(true),
  evidenceIds: z.array(z.string().uuid()),
  reason: z.string().min(1),
  limitations: z.array(z.string()),
});

export const supplementComparisonSchema = z.object({
  comparisonStatus: z.enum([
    "already_in_verified_estimate",
    "possible_missing_operation",
    "automatic_operation_excluded",
    "insufficient_evidence",
  ]),
  matchMethod: z.enum([
    "none",
    "operation_code_exact",
    "description_exact",
    "human_linked",
  ]),
  matchedEstimateLineId: z.string().uuid().nullable(),
  confidence: z.number().min(0).max(1),
  sourceQuality: z.enum(["source_document", "camera_only", "mixed", "unknown"]),
  evidenceIds: z.array(z.string().uuid()).min(1),
  reason: z.string().min(1),
  limitations: z.array(z.string()),
  humanReviewRequired: z.literal(true),
  canCreateSupplementCandidate: z.boolean(),
}).superRefine((result, context) => {
  if (
    result.comparisonStatus !== "possible_missing_operation"
    && result.canCreateSupplementCandidate
  ) {
    context.addIssue({
      code: "custom",
      path: ["canCreateSupplementCandidate"],
      message: "Only a possible missing operation may become a review candidate",
    });
  }
});

export type AiResult = z.infer<typeof aiResultSchema>;
export type HumanDecision = z.infer<typeof humanDecisionSchema>;
export type SupplementComparison = z.infer<typeof supplementComparisonSchema>;

export const estimateLineReviewDecisionSchema = z.enum([
  "confirmed",
  "corrected",
  "excluded",
  "needs_review",
]);

export type EstimateLineReviewDecision = z.infer<
  typeof estimateLineReviewDecisionSchema
>;

export const PRODUCT_LANGUAGE = {
  candidate: "Potential finding",
  supplement: "Possible supplement candidate",
  review: "Estimator review required",
  critical: "Critical review required",
  source: "Source verification required",
  evidence: "Evidence not documented",
  signoff: "Qualified-person sign-off required",
} as const;

export const PROHIBITED_AUTOMATIONS = [
  "approve_structural_repair",
  "approve_weld_quality",
  "approve_calibration",
  "submit_supplement",
  "modify_estimate",
  "release_vehicle",
  "sign_final_qc",
] as const;
