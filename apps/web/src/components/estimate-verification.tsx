"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  ArrowLeft,
  Check,
  CheckCircle2,
  ExternalLink,
  FileText,
  History,
  PencilLine,
  ScanLine,
  ShieldCheck,
  XCircle,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";
import { cn } from "@/lib/utils";

type ReviewDecision = "confirmed" | "corrected" | "excluded" | "needs_review";

type EstimateLine = {
  id: string;
  source_line_number: number | null;
  operation_code: string | null;
  description: string;
  amount: number | string | null;
  raw_text: string;
  parse_confidence: number | string | null;
  line_role: "estimate_operation" | "automatic_refinish_calculation";
};

type EstimateLineReview = {
  id: string;
  estimate_line_id: string;
  reviewer_id: string;
  decision: ReviewDecision;
  corrected_description: string | null;
  corrected_amount: number | string | null;
  note: string | null;
  supersedes_review_id: string | null;
  reviewed_at: string;
};

type Draft = { description: string; amount: string; note: string };

const finalDecisions = new Set<ReviewDecision>(["confirmed", "corrected", "excluded"]);

const decisionLabels: Record<ReviewDecision, string> = {
  confirmed: "Confirmed as parsed",
  corrected: "Human correction",
  excluded: "Excluded from estimate",
  needs_review: "Needs further review",
};

function formatAmount(value: number | string | null) {
  if (value === null || value === "") return "Not listed";
  const amount = Number(value);
  return Number.isFinite(amount)
    ? new Intl.NumberFormat("en-CA", { style: "currency", currency: "CAD" }).format(amount)
    : String(value);
}

function confidencePercent(value: number | string | null) {
  if (value === null) return null;
  const confidence = Number(value);
  return Number.isFinite(confidence) ? Math.round(confidence * 100) : null;
}

export function EstimateVerification({
  organizationName,
  repairOrder,
  estimate,
  lines,
  reviews,
  currentReviewerId,
}: {
  organizationName: string;
  repairOrder: { id: string; number: string; vehicle: string; vin: string | null };
  estimate: {
    id: string;
    versionNumber: number;
    parseStatus: string;
    parserName: string;
    parserVersion: string;
    importedAt: string;
    verifiedAt: string | null;
    sourceFilename: string;
    sourceSha256: string | null;
    sourceUrl: string | null;
  };
  lines: EstimateLine[];
  reviews: EstimateLineReview[];
  currentReviewerId: string;
}) {
  const router = useRouter();
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [editingLineId, setEditingLineId] = useState<string | null>(null);
  const [pendingLineId, setPendingLineId] = useState<string | null>(null);
  const [errors, setErrors] = useState<Record<string, string>>({});

  const latestByLine = useMemo(() => {
    const latest = new Map<string, EstimateLineReview>();
    for (const review of reviews) latest.set(review.estimate_line_id, review);
    return latest;
  }, [reviews]);

  const reviewableLines = lines.filter(
    (line) => line.line_role !== "automatic_refinish_calculation",
  );
  const automaticLineCount = lines.length - reviewableLines.length;
  const reviewedCount = reviewableLines.filter((line) => {
    const decision = latestByLine.get(line.id)?.decision;
    return decision ? finalDecisions.has(decision) : false;
  }).length;
  const verificationComplete =
    reviewableLines.length > 0 && reviewedCount === reviewableLines.length;

  function draftFor(line: EstimateLine) {
    return drafts[line.id] ?? {
      description: line.description,
      amount: line.amount === null ? "" : String(line.amount),
      note: "",
    };
  }

  function updateDraft(line: EstimateLine, patch: Partial<Draft>) {
    setDrafts((current) => ({ ...current, [line.id]: { ...draftFor(line), ...patch } }));
  }

  async function recordReview(line: EstimateLine, decision: ReviewDecision) {
    const draft = draftFor(line);
    if (decision === "corrected" && !draft.description.trim()) {
      setErrors((current) => ({ ...current, [line.id]: "Enter the corrected description." }));
      return;
    }
    if (decision !== "confirmed" && !draft.note.trim()) {
      setErrors((current) => ({ ...current, [line.id]: "Add a reason before recording this decision." }));
      return;
    }
    const correctedAmount = draft.amount.trim() === "" ? null : Number(draft.amount);
    if (decision === "corrected" && correctedAmount !== null && (!Number.isFinite(correctedAmount) || correctedAmount < 0)) {
      setErrors((current) => ({ ...current, [line.id]: "Enter a valid non-negative amount or leave it blank." }));
      return;
    }

    setPendingLineId(line.id);
    setErrors((current) => ({ ...current, [line.id]: "" }));
    const { error } = await createClient().rpc("record_estimate_line_review", {
      p_estimate_line_id: line.id,
      p_decision: decision,
      p_corrected_description: decision === "corrected" ? draft.description.trim() : null,
      p_corrected_amount: decision === "corrected" ? correctedAmount : null,
      p_note: decision === "confirmed" ? null : draft.note.trim(),
    });

    if (error) {
      setErrors((current) => ({ ...current, [line.id]: error.message }));
      setPendingLineId(null);
      return;
    }

    setDrafts((current) => ({ ...current, [line.id]: { ...draft, note: "" } }));
    setEditingLineId(null);
    setPendingLineId(null);
    router.refresh();
  }

  return (
    <main className="grid-noise min-h-screen">
      <header className="border-b border-white/8 bg-[#09131d]/90 px-4 py-4 backdrop-blur sm:px-8">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="grid size-10 place-items-center rounded-xl border border-cyan-300/25 bg-cyan-300/10 text-cyan-200"><ScanLine className="size-5" /></div>
            <div><div className="text-lg font-extrabold">nexa<span className="text-cyan-300">IQ</span></div><p className="text-xs text-slate-500">{organizationName}</p></div>
          </div>
          <Button asChild variant="ghost"><Link href="/"><ArrowLeft className="size-4" />Operations overview</Link></Button>
        </div>
      </header>

      <div className="mx-auto max-w-7xl space-y-6 px-4 py-7 sm:px-8">
        <section className="flex flex-col justify-between gap-5 lg:flex-row lg:items-start">
          <div>
            <div className="mb-3 flex flex-wrap items-center gap-2">
              <Badge variant={verificationComplete ? "green" : "amber"}>{verificationComplete ? "Human verification complete" : "Estimator verification required"}</Badge>
              <span className="text-xs text-slate-500">Estimate version {estimate.versionNumber}</span>
            </div>
            <h1 className="text-3xl font-bold">RO #{repairOrder.number} estimate review</h1>
            <p className="mt-2 text-slate-400">{repairOrder.vehicle}{repairOrder.vin ? ` · VIN ${repairOrder.vin}` : ""}</p>
          </div>
          <Card className="min-w-[280px] p-4">
            <div className="flex items-center justify-between text-sm"><span className="text-slate-400">Reviewable lines resolved</span><span className="font-bold">{reviewedCount} / {reviewableLines.length}</span></div>
            <div className="mt-3 h-2 overflow-hidden rounded-full bg-white/7"><div className="h-full rounded-full bg-cyan-300 transition-all" style={{ width: `${reviewableLines.length ? (reviewedCount / reviewableLines.length) * 100 : 0}%` }} /></div>
            {automaticLineCount > 0 && <p className="mt-3 text-xs text-cyan-200">{automaticLineCount} automatic refinish calculation{automaticLineCount === 1 ? "" : "s"} preserved separately.</p>}
            <p className="mt-3 text-xs leading-relaxed text-slate-500">This records source verification only. It is not repair approval, QC sign-off, or vehicle release.</p>
          </Card>
        </section>

        <Card className="border-cyan-300/15">
          <CardHeader>
            <div className="flex items-start gap-3"><FileText className="mt-0.5 size-5 text-cyan-200" /><div><h2 className="font-bold">Preserved source</h2><p className="mt-1 text-sm text-slate-400">Compare every parsed line against the original PDF before recording a decision.</p></div></div>
            {estimate.sourceUrl ? <Button asChild variant="secondary"><a href={estimate.sourceUrl} target="_blank" rel="noreferrer">Open original PDF <ExternalLink className="size-4" /></a></Button> : <Badge variant="amber">Source link unavailable</Badge>}
          </CardHeader>
          <CardContent className="grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-4">
            <div><p className="text-xs uppercase tracking-wider text-slate-600">File</p><p className="mt-1 truncate font-medium">{estimate.sourceFilename}</p></div>
            <div><p className="text-xs uppercase tracking-wider text-slate-600">Imported</p><p className="mt-1 font-medium">{new Date(estimate.importedAt).toLocaleString("en-CA")}</p></div>
            <div><p className="text-xs uppercase tracking-wider text-slate-600">Parser</p><p className="mt-1 font-medium">{estimate.parserName} {estimate.parserVersion}</p></div>
            <div><p className="text-xs uppercase tracking-wider text-slate-600">SHA-256</p><p className="mt-1 truncate font-mono text-xs text-slate-400" title={estimate.sourceSha256 ?? undefined}>{estimate.sourceSha256 ?? "Not available"}</p></div>
          </CardContent>
        </Card>

        {lines.length === 0 ? (
          <Card className="border-amber-300/20 p-8 text-center">
            <AlertTriangle className="mx-auto size-9 text-amber-200" />
            <h2 className="mt-4 text-xl font-bold">No estimate lines were extracted</h2>
            <p className="mt-2 text-sm text-slate-400">The original file is preserved, but this version cannot be verified automatically. Review the PDF and import a clearer export.</p>
          </Card>
        ) : (
          <section className="space-y-4" aria-label="Parsed estimate lines">
            {lines.map((line, index) => {
              const latest = latestByLine.get(line.id);
              const draft = draftFor(line);
              const confidence = confidencePercent(line.parse_confidence);
              const isAutomatic = line.line_role === "automatic_refinish_calculation";
              const isEditing = editingLineId === line.id;
              const isPending = pendingLineId === line.id;
              const effectiveDescription = latest?.decision === "corrected" ? latest.corrected_description : line.description;
              const effectiveAmount = latest?.decision === "corrected" ? latest.corrected_amount : line.amount;

              return (
                <Card key={line.id} className={cn("overflow-hidden", isAutomatic && "border-cyan-300/20 bg-cyan-300/[.03]", latest?.decision === "needs_review" && "border-amber-300/25", latest?.decision === "excluded" && "opacity-75")}>
                  <CardHeader className="gap-4">
                    <div className="flex min-w-0 items-start gap-3">
                      <span className="grid size-9 shrink-0 place-items-center rounded-lg bg-white/5 text-sm font-bold text-slate-300">{index + 1}</span>
                      <div className="min-w-0">
                        <div className="flex flex-wrap items-center gap-2">
                          <h2 className={cn("font-bold", latest?.decision === "excluded" && "line-through")}>{effectiveDescription}</h2>
                          {line.operation_code && <Badge>{line.operation_code}</Badge>}
                        </div>
                        <p className="mt-1 text-sm text-slate-400">{formatAmount(effectiveAmount)}{confidence !== null ? ` · Parser confidence ${confidence}%` : ""}</p>
                      </div>
                    </div>
                    {isAutomatic ? <Badge variant="cyan">Automatically included</Badge> : latest ? <Badge variant={latest.decision === "confirmed" || latest.decision === "corrected" ? "green" : latest.decision === "needs_review" ? "amber" : "rose"}>{decisionLabels[latest.decision]}</Badge> : <Badge variant="amber">Unreviewed</Badge>}
                  </CardHeader>

                  <CardContent className="space-y-4">
                    <div className="rounded-xl border border-white/7 bg-black/15 p-4">
                      <p className="text-xs font-bold uppercase tracking-wider text-slate-500">Raw PDF text · source line {line.source_line_number ?? "unknown"}</p>
                      <p className="mt-2 whitespace-pre-wrap font-mono text-xs leading-relaxed text-slate-300">{line.raw_text}</p>
                    </div>

                    {isAutomatic ? (
                      <div className="rounded-xl border border-cyan-300/15 bg-cyan-300/[.04] p-4 text-sm leading-relaxed text-cyan-100">
                        Clear coat is an automatic calculation tied to refinish operations. It is preserved from the source estimate for traceability and does not require a separate review decision.
                      </div>
                    ) : (<>
                    {latest && (
                      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-slate-500">
                        <span className="flex items-center gap-1.5"><History className="size-3.5" />Recorded {new Date(latest.reviewed_at).toLocaleString("en-CA")}</span>
                        <span>Reviewer {latest.reviewer_id === currentReviewerId ? "you" : latest.reviewer_id.slice(0, 8)}</span>
                        {latest.note && <span className="basis-full text-slate-400">Reason: {latest.note}</span>}
                      </div>
                    )}

                    {isEditing && (
                      <div className="grid gap-4 rounded-xl border border-cyan-300/15 bg-cyan-300/[.04] p-4 sm:grid-cols-[1fr_180px]">
                        <label className="text-sm font-medium">Corrected description
                          <input className="mt-2 h-11 w-full rounded-lg border border-white/10 bg-black/20 px-3 text-slate-100 outline-none focus:border-cyan-300/50" value={draft.description} onChange={(event) => updateDraft(line, { description: event.target.value })} />
                        </label>
                        <label className="text-sm font-medium">Corrected amount (CAD)
                          <input className="mt-2 h-11 w-full rounded-lg border border-white/10 bg-black/20 px-3 text-slate-100 outline-none focus:border-cyan-300/50" inputMode="decimal" value={draft.amount} onChange={(event) => updateDraft(line, { amount: event.target.value })} />
                        </label>
                        <label className="text-sm font-medium sm:col-span-2">Reason for correction
                          <textarea className="mt-2 min-h-24 w-full rounded-lg border border-white/10 bg-black/20 p-3 text-slate-100 outline-none focus:border-cyan-300/50" value={draft.note} onChange={(event) => updateDraft(line, { note: event.target.value })} placeholder="Describe what the source PDF shows and why the parsed value changed." />
                        </label>
                      </div>
                    )}

                    {!isEditing && (
                      <label className="block text-sm font-medium">Review note <span className="font-normal text-slate-500">(required to exclude or flag)</span>
                        <textarea className="mt-2 min-h-20 w-full rounded-lg border border-white/10 bg-black/20 p-3 text-slate-100 outline-none focus:border-cyan-300/50" value={draft.note} onChange={(event) => updateDraft(line, { note: event.target.value })} placeholder="Add source-specific context when the line is not confirmed as shown." />
                      </label>
                    )}

                    {errors[line.id] && <p className="text-sm text-rose-200" role="alert">{errors[line.id]}</p>}

                    <div className="flex flex-wrap gap-2">
                      {isEditing ? (
                        <>
                          <Button disabled={isPending} onClick={() => void recordReview(line, "corrected")}><Check className="size-4" />{isPending ? "Recording…" : "Save human correction"}</Button>
                          <Button disabled={isPending} variant="ghost" onClick={() => setEditingLineId(null)}>Cancel</Button>
                        </>
                      ) : (
                        <>
                          <Button disabled={isPending} onClick={() => void recordReview(line, "confirmed")}><CheckCircle2 className="size-4" />{isPending ? "Recording…" : "Confirm as parsed"}</Button>
                          <Button disabled={isPending} variant="secondary" onClick={() => setEditingLineId(line.id)}><PencilLine className="size-4" />Correct</Button>
                          <Button disabled={isPending} variant="secondary" onClick={() => void recordReview(line, "needs_review")}><AlertTriangle className="size-4" />Needs review</Button>
                          <Button disabled={isPending} variant="danger" onClick={() => void recordReview(line, "excluded")}><XCircle className="size-4" />Exclude</Button>
                        </>
                      )}
                    </div>
                    </>)}
                  </CardContent>
                </Card>
              );
            })}
          </section>
        )}

        <Card className="border-cyan-300/15 bg-gradient-to-br from-cyan-300/8 to-transparent p-5">
          <div className="flex items-start gap-3"><ShieldCheck className="mt-0.5 size-5 text-cyan-200" /><div><h2 className="font-bold">Human control remains active</h2><p className="mt-1 text-sm leading-relaxed text-slate-400">Each new decision supersedes the prior review without deleting history. The imported file and parser output remain preserved for comparison and audit.</p></div></div>
        </Card>
      </div>
    </main>
  );
}
