"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  ArrowLeft,
  CheckCircle2,
  ClipboardCheck,
  ExternalLink,
  FileCheck2,
  FileText,
  LoaderCircle,
  PackageCheck,
  RotateCcw,
  ShieldCheck,
  XCircle,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";

const APPROVAL_ATTESTATION =
  "I confirm that I reviewed this supplement package and its linked evidence. This is an estimator decision and does not certify repair safety or insurer payment.";

type Candidate = {
  id: string;
  finding_id: string;
  proposed_operation: string | null;
  reason: string;
  status: string;
  review_note: string | null;
  oem_consideration_status: string;
  oem_source_document_id: string | null;
  oem_source_note: string | null;
  reviewed_at: string | null;
  created_at: string;
};

type Finding = {
  id: string;
  component: string | null;
  condition: string | null;
  confidence: number | string | null;
  source_quality: string;
  comparison_status: string;
  limitations: unknown;
};

type ReviewDraft = {
  reason: string;
  oemStatus: string;
  documentId: string;
  oemNote: string;
};

type ReviewPackage = {
  id: string;
  package_number: number;
  status: string;
  approval_note: string | null;
  approved_at: string | null;
  created_at: string;
  itemCount: number;
};

type Evidence = {
  finding_id: string;
  media_id: string;
  evidence_role: string;
  original_filename: string;
  content_sha256: string;
  signedUrl: string | null;
};

type SourceDocument = {
  id: string;
  title: string;
  revision: string | null;
  applicability: string | null;
  sourceName: string | null;
  sectionReference: string | null;
};

type AuditEvent = {
  id: string;
  event_type: string;
  occurred_at: string;
  payload: unknown;
};

const statusTone = (status: string): "green" | "amber" | "rose" | "cyan" | "slate" => {
  if (status === "confirmed" || status === "approved") return "green";
  if (status === "dismissed" || status === "changes_requested") return "rose";
  if (status === "estimator_review" || status === "review_reopened") return "amber";
  return "slate";
};

export function SupplementReview({
  organizationId,
  organizationName,
  repairOrder,
  candidates,
  findings,
  evidence,
  documents,
  packages,
  auditEvents,
}: {
  organizationId: string;
  organizationName: string;
  repairOrder: { id: string; number: string; vehicle: string; vin: string | null };
  candidates: Candidate[];
  findings: Finding[];
  evidence: Evidence[];
  documents: SourceDocument[];
  packages: ReviewPackage[];
  auditEvents: AuditEvent[];
}) {
  const router = useRouter();
  const [drafts, setDrafts] = useState<Record<string, ReviewDraft>>({});
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [creatingPackage, setCreatingPackage] = useState(false);
  const [packageNote, setPackageNote] = useState("");
  const [attestationAccepted, setAttestationAccepted] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const findingById = useMemo(() => new Map(findings.map((finding) => [finding.id, finding])), [findings]);
  const readyCount = candidates.filter((candidate) => candidate.status === "confirmed").length;
  const pendingCount = candidates.filter((candidate) => ["estimator_review", "review_reopened"].includes(candidate.status)).length;
  const latestPackage = packages[0] ?? null;

  async function apiHeaders(contentType = false) {
    const { data } = await createClient().auth.getSession();
    if (!data.session?.access_token) throw new Error("Your session expired. Sign in again.");
    return {
      Authorization: `Bearer ${data.session.access_token}`,
      "X-NexaIQ-Organization-ID": organizationId,
      ...(contentType ? { "Content-Type": "application/json" } : {}),
    };
  }

  function draftFor(candidate: Candidate): ReviewDraft {
    return drafts[candidate.id] ?? {
      reason: candidate.review_note ?? "",
      oemStatus: candidate.oem_consideration_status === "not_reviewed" ? "review_recommended" : candidate.oem_consideration_status,
      documentId: candidate.oem_source_document_id ?? "",
      oemNote: candidate.oem_source_note ?? "",
    };
  }

  function updateDraft(candidate: Candidate, patch: Partial<ReviewDraft>) {
    setDrafts((current) => ({ ...current, [candidate.id]: { ...draftFor(candidate), ...patch } }));
  }

  async function recordReview(candidate: Candidate, decision: "ready_for_package" | "needs_changes" | "excluded") {
    const draft = draftFor(candidate);
    if (decision !== "ready_for_package" && draft.reason.trim().length < 3) {
      setMessage("Add a short review reason before requesting changes or excluding a candidate.");
      return;
    }
    if (decision === "ready_for_package" && draft.oemStatus === "review_recommended") {
      setMessage("Resolve the OEM/source consideration before marking this candidate ready.");
      return;
    }
    if (draft.oemStatus === "source_reviewed" && !draft.documentId) {
      setMessage("Choose the OEM/source document that was reviewed.");
      return;
    }
    if (draft.oemStatus === "source_unavailable" && draft.oemNote.trim().length < 3) {
      setMessage("Explain why the OEM/source document is unavailable.");
      return;
    }

    setPendingId(candidate.id);
    setMessage(null);
    const { error } = await createClient().from("supplement_candidate_review_events").insert({
      supplement_candidate_id: candidate.id,
      decision,
      review_reason: draft.reason.trim() || null,
      oem_consideration_status: draft.oemStatus,
      oem_source_document_id: draft.documentId || null,
      oem_source_note: draft.oemNote.trim() || null,
    });
    if (error) setMessage(error.message);
    else {
      setMessage("Estimator review recorded in the append-only history.");
      router.refresh();
    }
    setPendingId(null);
  }

  async function createPackage() {
    setCreatingPackage(true);
    setMessage(null);
    try {
      const headers = await apiHeaders();
      const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
      const response = await fetch(`${apiUrl}/v1/supplement-analysis/repair-orders/${repairOrder.id}/review-packages`, { method: "POST", headers });
      const row = await response.json().catch(() => ({})) as { package_number?: number; item_count?: number; detail?: string };
      if (!response.ok) throw new Error(row.detail ?? "Review package creation failed.");
      setMessage(`Review package ${row.package_number ?? ""} created from ${row.item_count ?? readyCount} ready candidate(s).`);
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Review package creation failed.");
    }
    setCreatingPackage(false);
  }

  async function decidePackage(decision: "approved" | "changes_requested") {
    if (!latestPackage) return;
    if (decision === "approved" && !attestationAccepted) {
      setMessage("Accept the estimator attestation before approving this package.");
      return;
    }
    if (decision === "changes_requested" && packageNote.trim().length < 3) {
      setMessage("Add a short reason describing the requested changes.");
      return;
    }
    setPendingId(latestPackage.id);
    setMessage(null);
    try {
      const headers = await apiHeaders(true);
      const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
      const response = await fetch(`${apiUrl}/v1/supplement-analysis/review-packages/${latestPackage.id}/decision`, {
        method: "POST",
        headers,
        body: JSON.stringify({ decision, note: packageNote.trim() || null, attestation: decision === "approved" ? APPROVAL_ATTESTATION : null }),
      });
      const body = await response.json().catch(() => ({})) as { detail?: string };
      if (!response.ok) throw new Error(body.detail ?? "Package decision failed.");
      setMessage(decision === "approved" ? "Package approved by the estimator." : "Changes requested and recorded.");
      setAttestationAccepted(false);
      setPackageNote("");
      router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Package decision failed.");
    }
    setPendingId(null);
  }

  return (
    <main className="grid-noise min-h-screen">
      <header className="border-b border-white/8 bg-[#09131d]/90 px-4 py-4 backdrop-blur sm:px-8">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3"><div className="grid size-10 place-items-center rounded-xl border border-cyan-300/25 bg-cyan-300/10 text-cyan-200"><ClipboardCheck className="size-5" /></div><div><div className="text-lg font-extrabold">nexa<span className="text-cyan-300">IQ</span></div><p className="text-xs text-slate-500">{organizationName}</p></div></div>
          <Button asChild variant="ghost"><Link href={`/repair-orders/${repairOrder.id}/supplement-analysis`}><ArrowLeft className="size-4" />Candidate analysis</Link></Button>
        </div>
      </header>

      <div className="mx-auto max-w-7xl space-y-6 px-4 py-7 sm:px-8">
        <section className="flex flex-col justify-between gap-5 lg:flex-row lg:items-start">
          <div><div className="mb-3 flex flex-wrap items-center gap-2"><Badge variant="cyan">Stage 5</Badge><Badge variant="amber">Estimator approval required</Badge></div><h1 className="text-3xl font-bold">RO #{repairOrder.number} supplement review</h1><p className="mt-2 text-slate-400">{repairOrder.vehicle}{repairOrder.vin ? ` · VIN ${repairOrder.vin}` : ""}</p></div>
          <Button size="lg" disabled={creatingPackage || readyCount === 0} onClick={() => void createPackage()}>{creatingPackage ? <LoaderCircle className="size-4 animate-spin" /> : <PackageCheck className="size-4" />}{creatingPackage ? "Creating package…" : "Create review package"}</Button>
        </section>

        <section className="grid gap-3 sm:grid-cols-3">
          <Card className="p-5"><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Awaiting review</p><p className="mt-2 text-3xl font-bold text-amber-100">{pendingCount}</p></Card>
          <Card className="p-5"><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Package ready</p><p className="mt-2 text-3xl font-bold text-emerald-100">{readyCount}</p></Card>
          <Card className="p-5"><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Report versions</p><p className="mt-2 text-3xl font-bold">{packages.length}</p></Card>
        </section>

        {message && <div className="rounded-xl border border-cyan-300/20 bg-cyan-300/5 px-4 py-3 text-sm text-cyan-100" role="status">{message}</div>}

        <section className="space-y-4" aria-label="Supplement candidates for estimator review">
          <div><h2 className="text-xl font-bold">Confirmed findings</h2><p className="mt-1 text-sm text-slate-500">Resolve the source consideration and review each operation before it can enter a report.</p></div>
          {candidates.length === 0 ? <Card className="p-8 text-center"><FileCheck2 className="mx-auto size-9 text-slate-500" /><h3 className="mt-4 text-lg font-bold">No confirmed findings yet</h3><p className="mt-2 text-sm text-slate-400">Confirm a candidate in Stage 4 to begin supplement review. Paid AI remains disabled.</p></Card> : candidates.map((candidate) => {
            const finding = findingById.get(candidate.finding_id);
            const candidateEvidence = evidence.filter((item) => item.finding_id === candidate.finding_id);
            const draft = draftFor(candidate);
            const pending = pendingId === candidate.id;
            const limitations = Array.isArray(finding?.limitations) ? finding.limitations.filter((item): item is string => typeof item === "string") : [];
            return <Card key={candidate.id} className="overflow-hidden">
              <CardHeader><div><div className="mb-2 flex flex-wrap items-center gap-2"><Badge variant={statusTone(candidate.status)}>{candidate.status.replaceAll("_", " ")}</Badge>{finding && <Badge>{finding.comparison_status.replaceAll("_", " ")}</Badge>}{finding?.confidence != null && <span className="text-xs text-slate-500">AI confidence {Math.round(Number(finding.confidence) * 100)}% · human confirmation required</span>}</div><h3 className="text-lg font-bold">{candidate.proposed_operation || "Operation requires estimator entry"}</h3><p className="mt-1 text-sm text-slate-500">{[finding?.component, finding?.condition].filter(Boolean).join(" · ") || "Visible-condition candidate"}</p></div><span className="text-xs text-slate-600">{new Date(candidate.created_at).toLocaleString("en-CA")}</span></CardHeader>
              <CardContent className="space-y-5">
                <div className="rounded-xl border border-white/7 bg-black/15 p-4"><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Why this needs review</p><p className="mt-2 text-sm leading-relaxed text-slate-300">{candidate.reason}</p>{limitations.length > 0 && <p className="mt-2 text-xs text-amber-100">Limitations: {limitations.join(" · ")}</p>}</div>
                <div><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Original evidence</p><div className="mt-2 flex flex-wrap gap-2">{candidateEvidence.length ? candidateEvidence.map((item) => item.signedUrl ? <Button asChild variant="secondary" size="sm" key={item.media_id}><a href={item.signedUrl} target="_blank" rel="noreferrer">{item.original_filename}<ExternalLink className="size-3.5" /></a></Button> : <Badge key={item.media_id}>{item.original_filename}</Badge>) : <span className="text-sm text-amber-100">Evidence link unavailable—do not approve without verifying the source.</span>}</div></div>
                <div className="grid gap-4 lg:grid-cols-2">
                  <label className="text-sm font-medium">OEM/source consideration<select className="mt-2 h-11 w-full rounded-lg border border-white/10 bg-[#0b1722] px-3 text-slate-100 outline-none focus:border-cyan-300/50" value={draft.oemStatus} onChange={(event) => updateDraft(candidate, { oemStatus: event.target.value })}><option value="review_recommended">Review recommended</option><option value="source_reviewed">Authorized source reviewed</option><option value="source_unavailable">Source unavailable</option><option value="not_applicable">Not applicable</option></select></label>
                  <label className="text-sm font-medium">Reviewed source document<select className="mt-2 h-11 w-full rounded-lg border border-white/10 bg-[#0b1722] px-3 text-slate-100 outline-none focus:border-cyan-300/50" value={draft.documentId} onChange={(event) => updateDraft(candidate, { documentId: event.target.value })} disabled={draft.oemStatus !== "source_reviewed"}><option value="">Select a document</option>{documents.map((document) => <option value={document.id} key={document.id}>{document.title}{document.revision ? ` · ${document.revision}` : ""}</option>)}</select></label>
                </div>
                <label className="block text-sm font-medium">OEM/source note<textarea className="mt-2 min-h-20 w-full rounded-lg border border-white/10 bg-black/20 p-3 text-slate-100 outline-none focus:border-cyan-300/50" value={draft.oemNote} onChange={(event) => updateDraft(candidate, { oemNote: event.target.value })} placeholder="Applicability, section checked, or why the source is unavailable." /></label>
                <label className="block text-sm font-medium">Estimator review note<textarea className="mt-2 min-h-20 w-full rounded-lg border border-white/10 bg-black/20 p-3 text-slate-100 outline-none focus:border-cyan-300/50" value={draft.reason} onChange={(event) => updateDraft(candidate, { reason: event.target.value })} placeholder="Required for changes or exclusion; optional when package-ready." /></label>
                <div className="flex flex-wrap gap-2"><Button disabled={pending} onClick={() => void recordReview(candidate, "ready_for_package")}><CheckCircle2 className="size-4" />Ready for package</Button><Button disabled={pending} variant="secondary" onClick={() => void recordReview(candidate, "needs_changes")}><RotateCcw className="size-4" />Needs changes</Button><Button disabled={pending} variant="danger" onClick={() => void recordReview(candidate, "excluded")}><XCircle className="size-4" />Exclude</Button></div>
              </CardContent>
            </Card>;
          })}
        </section>

        <section className="space-y-4">
          <div><h2 className="text-xl font-bold">Review packages</h2><p className="mt-1 text-sm text-slate-500">Each package is a frozen snapshot. Later candidate changes cannot silently rewrite it.</p></div>
          {!latestPackage ? <Card className="p-8 text-center"><FileText className="mx-auto size-9 text-slate-500" /><h3 className="mt-4 text-lg font-bold">No report package yet</h3><p className="mt-2 text-sm text-slate-400">Mark at least one candidate package-ready, then create the first report.</p></Card> : <Card>
            <CardHeader><div><div className="mb-2 flex items-center gap-2"><Badge variant={statusTone(latestPackage.status)}>{latestPackage.status.replaceAll("_", " ")}</Badge><span className="text-xs text-slate-500">Version {latestPackage.package_number}</span></div><h3 className="text-lg font-bold">Supplement Review Package #{latestPackage.package_number}</h3><p className="mt-1 text-sm text-slate-500">{latestPackage.itemCount} frozen item(s) · Created {new Date(latestPackage.created_at).toLocaleString("en-CA")}</p></div><Button asChild variant="secondary"><Link href={`/repair-orders/${repairOrder.id}/supplement-review/report/${latestPackage.id}`}><FileText className="size-4" />Open printable report</Link></Button></CardHeader>
            <CardContent className="space-y-4">
              {latestPackage.status !== "approved" && <><label className="block text-sm font-medium">Package decision note<textarea className="mt-2 min-h-20 w-full rounded-lg border border-white/10 bg-black/20 p-3 text-slate-100 outline-none focus:border-cyan-300/50" value={packageNote} onChange={(event) => setPackageNote(event.target.value)} placeholder="Required when requesting changes; optional for approval." /></label><label className="flex items-start gap-3 rounded-xl border border-white/8 bg-black/15 p-4 text-sm"><input className="mt-1 size-4 accent-cyan-300" type="checkbox" checked={attestationAccepted} onChange={(event) => setAttestationAccepted(event.target.checked)} /><span><span className="font-semibold text-slate-200">Estimator attestation</span><span className="mt-1 block leading-relaxed text-slate-400">{APPROVAL_ATTESTATION}</span></span></label><div className="flex flex-wrap gap-2"><Button disabled={pendingId === latestPackage.id} onClick={() => void decidePackage("approved")}><CheckCircle2 className="size-4" />Approve package</Button><Button disabled={pendingId === latestPackage.id} variant="secondary" onClick={() => void decidePackage("changes_requested")}><AlertTriangle className="size-4" />Request changes</Button></div></>}
              {latestPackage.status === "approved" && <p className="flex items-center gap-2 text-sm text-emerald-200"><CheckCircle2 className="size-4" />Estimator approved {latestPackage.approved_at ? new Date(latestPackage.approved_at).toLocaleString("en-CA") : ""}. No insurer submission occurred.</p>}
            </CardContent>
          </Card>}
        </section>

        <Card><CardHeader><div><h2 className="font-bold">Stage 5 audit history</h2><p className="mt-1 text-sm text-slate-500">Append-oriented review events for this repair order.</p></div></CardHeader><CardContent>{auditEvents.length ? <ol className="space-y-3">{auditEvents.map((event) => <li className="flex flex-wrap items-center justify-between gap-2 border-b border-white/6 pb-3 text-sm" key={event.id}><span>{event.event_type.replaceAll("_", " ")}</span><span className="text-xs text-slate-500">{new Date(event.occurred_at).toLocaleString("en-CA")}</span></li>)}</ol> : <p className="text-sm text-slate-500">No Stage 5 audit events yet.</p>}</CardContent></Card>

        <Card className="border-cyan-300/15 bg-gradient-to-br from-cyan-300/8 to-transparent p-5"><div className="flex items-start gap-3"><ShieldCheck className="mt-0.5 size-5 text-cyan-200" /><div><h2 className="font-bold">Decision-support boundary</h2><p className="mt-1 text-sm leading-relaxed text-slate-400">A package organizes estimator-reviewed candidates and evidence. It does not change Mitchell, submit to an insurer, guarantee payment, or certify the physical repair.</p></div></div></Card>
      </div>
    </main>
  );
}
