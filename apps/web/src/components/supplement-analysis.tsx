"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  AlertTriangle,
  ArrowLeft,
  CheckCircle2,
  ExternalLink,
  Eye,
  LoaderCircle,
  RefreshCw,
  ScanSearch,
  ShieldCheck,
  XCircle,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/client";

type Finding = {
  id: string;
  finding_type: string;
  component: string | null;
  condition: string | null;
  status: string;
  confidence: number | string | null;
  source_quality: string;
  reason: string;
  limitations: unknown;
  proposed_operation: string | null;
  comparison_status: string;
  match_method: string;
  created_at: string;
};

type Readiness = {
  ready: boolean;
  blockers: string[];
  photo_count: number;
  eligible_photo_count: number;
  withheld_photo_count: number;
  voice_note_count: number;
};

type ReviewDecision =
  | "confirmed"
  | "dismissed"
  | "needs_review"
  | "more_evidence_requested";

const blockerLabels: Record<string, string> = {
  verified_estimate_required: "Finish human verification of the latest estimate.",
  photo_evidence_required: "Capture at least one teardown photo.",
  privacy_eligible_photo_required: "All photos are withheld by privacy flags.",
  approved_provider_policy_required: "Approve the organization’s OpenAI data policy.",
  evaluated_model_required: "Activate an evaluated model configuration.",
  server_secret_required: "Add the server-only Supabase secret key to the API.",
  provider_credential_required: "Add the server-only OpenAI API key to the API.",
};

const statusTone = (status: string): "green" | "amber" | "rose" | "slate" => {
  if (status === "confirmed") return "green";
  if (status === "dismissed") return "rose";
  if (status === "candidate") return "amber";
  return "slate";
};

export function SupplementAnalysis({
  organizationId,
  organizationName,
  repairOrder,
  findings,
  jobs,
  evidenceLinks,
  media,
}: {
  organizationId: string;
  organizationName: string;
  repairOrder: { id: string; number: string; vehicle: string; vin: string | null };
  findings: Finding[];
  jobs: Array<{
    id: string;
    status: string;
    failure_code: string | null;
    started_at: string | null;
    completed_at: string | null;
    created_at: string;
  }>;
  evidenceLinks: Array<{ finding_id: string; media_id: string; evidence_role: string }>;
  media: Array<{
    id: string;
    original_filename: string;
    mime_type: string;
    content_sha256: string;
    signedUrl: string | null;
  }>;
}) {
  const router = useRouter();
  const [readiness, setReadiness] = useState<Readiness | null>(null);
  const [loadingReadiness, setLoadingReadiness] = useState(true);
  const [running, setRunning] = useState(false);
  const [pendingFinding, setPendingFinding] = useState<string | null>(null);
  const [reasons, setReasons] = useState<Record<string, string>>({});
  const [message, setMessage] = useState<string | null>(null);
  const mediaById = useMemo(() => new Map(media.map((item) => [item.id, item])), [media]);

  async function apiHeaders() {
    const { data } = await createClient().auth.getSession();
    if (!data.session?.access_token) throw new Error("Your session expired. Sign in again.");
    return {
      Authorization: `Bearer ${data.session.access_token}`,
      "X-NexaIQ-Organization-ID": organizationId,
    };
  }

  async function loadReadiness() {
    setLoadingReadiness(true);
    try {
      const headers = await apiHeaders();
      const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
      const response = await fetch(
        `${apiUrl}/v1/supplement-analysis/repair-orders/${repairOrder.id}/readiness`,
        { headers, cache: "no-store" },
      );
      const body = (await response.json().catch(() => ({}))) as Readiness & { detail?: string };
      if (!response.ok) throw new Error(body.detail ?? "Readiness check failed.");
      setReadiness(body);
      setMessage(null);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Readiness check failed.");
    } finally {
      setLoadingReadiness(false);
    }
  }

  useEffect(() => {
    // Readiness is external API state and must be loaded after the browser session is available.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void loadReadiness();
    // Readiness is refreshed after every analysis run; repairOrder.id is stable on this page.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [repairOrder.id]);

  async function runAnalysis() {
    setRunning(true);
    setMessage(null);
    try {
      const headers = await apiHeaders();
      const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
      const response = await fetch(
        `${apiUrl}/v1/supplement-analysis/repair-orders/${repairOrder.id}/runs`,
        {
          method: "POST",
          headers: { ...headers, "Idempotency-Key": crypto.randomUUID() },
        },
      );
      const body = (await response.json().catch(() => ({}))) as {
        created_finding_count?: number;
        detail?: string;
      };
      if (!response.ok) throw new Error(body.detail ?? "Analysis failed.");
      setMessage(
        `${body.created_finding_count ?? 0} reviewable finding(s) created. No estimate was changed.`,
      );
      router.refresh();
      await loadReadiness();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Analysis failed.");
    } finally {
      setRunning(false);
    }
  }

  async function review(findingId: string, decision: ReviewDecision) {
    const reason = reasons[findingId]?.trim() ?? "";
    if (decision !== "confirmed" && reason.length < 3) {
      setMessage("Add a short reason before recording that decision.");
      return;
    }
    setPendingFinding(findingId);
    setMessage(null);
    const { error } = await createClient().rpc("record_finding_review", {
      p_finding_id: findingId,
      p_decision: decision,
      p_reason: decision === "confirmed" ? null : reason,
    });
    if (error) setMessage(error.message);
    else {
      setMessage("Human review recorded in the append-only evaluation history.");
      router.refresh();
    }
    setPendingFinding(null);
  }

  return (
    <main className="grid-noise min-h-screen">
      <header className="border-b border-white/8 bg-[#09131d]/90 px-4 py-4 backdrop-blur sm:px-8">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="grid size-10 place-items-center rounded-xl border border-cyan-300/25 bg-cyan-300/10 text-cyan-200"><ScanSearch className="size-5" /></div>
            <div><div className="text-lg font-extrabold">nexa<span className="text-cyan-300">IQ</span></div><p className="text-xs text-slate-500">{organizationName}</p></div>
          </div>
          <Button asChild variant="ghost"><Link href="/"><ArrowLeft className="size-4" />Operations overview</Link></Button>
        </div>
      </header>

      <div className="mx-auto max-w-7xl space-y-6 px-4 py-7 sm:px-8">
        <section className="flex flex-col justify-between gap-5 lg:flex-row lg:items-start">
          <div>
            <div className="mb-3 flex flex-wrap items-center gap-2"><Badge variant="cyan">Stage 4</Badge><Badge variant="amber">Human review required</Badge></div>
            <h1 className="text-3xl font-bold">RO #{repairOrder.number} supplement analysis</h1>
            <p className="mt-2 text-slate-400">{repairOrder.vehicle}{repairOrder.vin ? ` · VIN ${repairOrder.vin}` : ""}</p>
          </div>
          <Button disabled={running || loadingReadiness || !readiness?.ready} size="lg" onClick={() => void runAnalysis()}>
            {running ? <LoaderCircle className="size-4 animate-spin" /> : <ScanSearch className="size-4" />}
            {running ? "Analyzing private evidence…" : "Run candidate analysis"}
          </Button>
        </section>

        <Card className={readiness?.ready ? "border-emerald-300/20" : "border-amber-300/20"}>
          <CardHeader>
            <div><h2 className="font-bold">Run readiness</h2><p className="mt-1 text-sm text-slate-400">Only privacy-eligible photos and the verified estimate are sent to the approved provider.</p></div>
            <Button variant="ghost" size="sm" onClick={() => void loadReadiness()} disabled={loadingReadiness}><RefreshCw className={loadingReadiness ? "size-4 animate-spin" : "size-4"} />Refresh</Button>
          </CardHeader>
          <CardContent>
            {loadingReadiness ? <p className="text-sm text-slate-400">Checking controls…</p> : readiness ? (
              <div className="space-y-4">
                <div className="grid gap-3 sm:grid-cols-4">
                  <div><p className="text-xs uppercase tracking-wider text-slate-600">Photos</p><p className="mt-1 text-xl font-bold">{readiness.photo_count}</p></div>
                  <div><p className="text-xs uppercase tracking-wider text-slate-600">Eligible</p><p className="mt-1 text-xl font-bold text-emerald-200">{readiness.eligible_photo_count}</p></div>
                  <div><p className="text-xs uppercase tracking-wider text-slate-600">Withheld</p><p className="mt-1 text-xl font-bold text-amber-200">{readiness.withheld_photo_count}</p></div>
                  <div><p className="text-xs uppercase tracking-wider text-slate-600">Voice notes</p><p className="mt-1 text-xl font-bold">{readiness.voice_note_count}</p></div>
                </div>
                {readiness.ready ? <p className="flex items-center gap-2 text-sm text-emerald-200"><CheckCircle2 className="size-4" />All technical and governance controls are ready.</p> : <ul className="space-y-2 text-sm text-amber-100">{readiness.blockers.map((blocker) => <li key={blocker} className="flex items-start gap-2"><AlertTriangle className="mt-0.5 size-4 shrink-0" />{blockerLabels[blocker] ?? blocker}</li>)}</ul>}
              </div>
            ) : <p className="text-sm text-rose-200">Readiness is unavailable.</p>}
          </CardContent>
        </Card>

        {message && <div className="rounded-xl border border-cyan-300/20 bg-cyan-300/5 px-4 py-3 text-sm text-cyan-100" role="status">{message}</div>}

        <section className="space-y-4" aria-label="AI supplement candidates">
          <div><h2 className="text-xl font-bold">Reviewable findings</h2><p className="mt-1 text-sm text-slate-500">These are candidates only. Confirming creates an estimator-review item; it does not alter or submit the estimate.</p></div>
          {findings.length === 0 ? <Card className="p-8 text-center"><Eye className="mx-auto size-9 text-slate-500" /><h3 className="mt-4 text-lg font-bold">No candidate findings yet</h3><p className="mt-2 text-sm text-slate-400">When readiness is complete, run analysis to compare visible conditions with the verified estimate.</p></Card> : findings.map((finding) => {
            const limitations = Array.isArray(finding.limitations) ? finding.limitations.filter((item): item is string => typeof item === "string") : [];
            const sources = evidenceLinks.filter((link) => link.finding_id === finding.id).map((link) => ({ ...link, media: mediaById.get(link.media_id) }));
            const pending = pendingFinding === finding.id;
            return <Card key={finding.id} className="overflow-hidden">
              <CardHeader>
                <div><div className="mb-2 flex flex-wrap items-center gap-2"><Badge variant={statusTone(finding.status)}>{finding.status.replaceAll("_", " ")}</Badge><Badge>{finding.comparison_status.replaceAll("_", " ")}</Badge><span className="text-xs text-slate-500">Confidence {Math.round(Number(finding.confidence ?? 0) * 100)}%</span></div><h3 className="text-lg font-bold">{finding.proposed_operation ?? finding.finding_type}</h3><p className="mt-1 text-sm text-slate-500">{[finding.component, finding.condition].filter(Boolean).join(" · ") || "Visible-condition candidate"}</p></div>
                <span className="text-xs text-slate-600">{new Date(finding.created_at).toLocaleString("en-CA")}</span>
              </CardHeader>
              <CardContent className="space-y-5">
                <div className="rounded-xl border border-white/7 bg-black/15 p-4"><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Deterministic comparison rationale</p><p className="mt-2 text-sm leading-relaxed text-slate-300">{finding.reason}</p></div>
                <div className="grid gap-4 text-sm md:grid-cols-2"><div><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Limitations</p><ul className="mt-2 space-y-1 text-slate-400">{limitations.length ? limitations.map((item) => <li key={item}>• {item}</li>) : <li>• No additional limitation recorded.</li>}</ul></div><div><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Original evidence</p><div className="mt-2 flex flex-wrap gap-2">{sources.map((source) => source.media?.signedUrl ? <Button asChild variant="secondary" size="sm" key={source.media_id}><a href={source.media.signedUrl} target="_blank" rel="noreferrer">{source.media.original_filename}<ExternalLink className="size-3.5" /></a></Button> : <Badge key={source.media_id}>{source.media_id.slice(0, 8)}</Badge>)}</div></div></div>
                <label className="block text-sm font-medium">Review reason <span className="font-normal text-slate-500">(required unless confirming)</span><textarea className="mt-2 min-h-20 w-full rounded-lg border border-white/10 bg-black/20 p-3 text-slate-100 outline-none focus:border-cyan-300/50" value={reasons[finding.id] ?? ""} onChange={(event) => setReasons((current) => ({ ...current, [finding.id]: event.target.value }))} placeholder="Record what you verified or what evidence is still needed." /></label>
                <div className="flex flex-wrap gap-2"><Button disabled={pending} onClick={() => void review(finding.id, "confirmed")}><CheckCircle2 className="size-4" />Confirm candidate</Button><Button disabled={pending} variant="secondary" onClick={() => void review(finding.id, "needs_review")}><AlertTriangle className="size-4" />Needs review</Button><Button disabled={pending} variant="secondary" onClick={() => void review(finding.id, "more_evidence_requested")}><Eye className="size-4" />Request evidence</Button><Button disabled={pending} variant="danger" onClick={() => void review(finding.id, "dismissed")}><XCircle className="size-4" />Dismiss</Button></div>
              </CardContent>
            </Card>;
          })}
        </section>

        {jobs.length > 0 && <Card><CardHeader><div><h2 className="font-bold">Recent analysis runs</h2><p className="mt-1 text-sm text-slate-500">Operational status only; provider errors are stored as safe codes.</p></div></CardHeader><CardContent className="space-y-2 text-sm">{jobs.map((job) => <div className="flex flex-wrap items-center justify-between gap-2 border-b border-white/5 pb-2" key={job.id}><span className="font-mono text-xs text-slate-500">{job.id.slice(0, 8)}</span><Badge variant={job.status === "completed" ? "green" : job.status === "failed" ? "rose" : "amber"}>{job.status}</Badge><span className="text-slate-500">{new Date(job.created_at).toLocaleString("en-CA")}</span>{job.failure_code && <span className="text-rose-200">{job.failure_code}</span>}</div>)}</CardContent></Card>}

        <Card className="border-cyan-300/15 bg-gradient-to-br from-cyan-300/8 to-transparent p-5"><div className="flex items-start gap-3"><ShieldCheck className="mt-0.5 size-5 text-cyan-200" /><div><h2 className="font-bold">Human control remains active</h2><p className="mt-1 text-sm leading-relaxed text-slate-400">nexaIQ does not infer hidden damage, approve repair safety, modify estimate lines, or submit supplements. Every saved candidate retains its evidence links and append-only review history.</p></div></div></Card>
      </div>
    </main>
  );
}
