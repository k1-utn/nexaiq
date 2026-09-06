"use client";

import { useRef, useState } from "react";
import {
  AlertTriangle,
  ArrowUpRight,
  Bell,
  Building2,
  Check,
  ChevronDown,
  CircleDot,
  ClipboardCheck,
  FileSearch,
  Gauge,
  History,
  LayoutDashboard,
  Menu,
  MoreHorizontal,
  ScanLine,
  Search,
  Settings,
  ShieldCheck,
  Upload,
  Users,
  Wrench,
  X,
} from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { createClient as createBrowserSupabaseClient } from "@/lib/supabase/client";

type CandidateState = "pending" | "confirmed" | "dismissed" | "review";

const repairOrders = [
  { ro: "18472", vehicle: "2025 Toyota RAV4", estimator: "Sarah J.", estimate: "Supplement 1", status: "Estimator review", tone: "amber", updated: "8 min" },
  { ro: "18468", vehicle: "2023 Ford F-150", estimator: "Mike R.", estimate: "Original", status: "Evidence requested", tone: "rose", updated: "24 min" },
  { ro: "18461", vehicle: "2024 Honda CR-V", estimator: "Sarah J.", estimate: "Supplement 2", status: "Documentation complete", tone: "green", updated: "1 hr" },
  { ro: "18455", vehicle: "2022 Hyundai Tucson", estimator: "Andre L.", estimate: "Original", status: "Estimate verification", tone: "cyan", updated: "2 hr" },
] as const;

const navigation = [
  ["Overview", LayoutDashboard],
  ["Repair orders", Wrench],
  ["Supplement reviews", FileSearch],
  ["Critical reviews", AlertTriangle],
  ["Audit history", History],
] as const;

export function Dashboard({ organizationId, organizationName, repairOrderId }: { organizationId: string; organizationName: string; repairOrderId: string | null }) {
  const uploadRef = useRef<HTMLInputElement>(null);
  const [candidate, setCandidate] = useState<CandidateState>("pending");
  const [uploadState, setUploadState] = useState<"idle" | "uploading" | "done" | "error">("idle");
  const [fileName, setFileName] = useState("");
  const [mobileNavOpen, setMobileNavOpen] = useState(false);

  async function uploadEstimate(file?: File) {
    if (!file || !repairOrderId) {
      setUploadState("error");
      return;
    }
    setFileName(file.name);
    setUploadState("uploading");
    try {
      const form = new FormData();
      form.append("file", file);
      form.append("repair_order_id", repairOrderId);
      const apiUrl = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";
      const headers: Record<string, string> = { "X-NexaIQ-Organization-ID": organizationId };
      if (process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY) {
        const { data } = await createBrowserSupabaseClient().auth.getSession();
        if (data.session?.access_token) headers.Authorization = `Bearer ${data.session.access_token}`;
      }
      const response = await fetch(`${apiUrl}/v1/estimate-ingestion/parse`, {
        method: "POST",
        headers,
        body: form,
      });
      if (!response.ok) throw new Error("Upload failed");
      setUploadState("done");
    } catch {
      setUploadState("error");
    }
  }

  return (
    <div className="grid-noise min-h-screen lg:grid lg:grid-cols-[260px_1fr]">
      <aside className={cn("fixed inset-y-0 left-0 z-30 w-[260px] border-r border-white/8 bg-[#071018]/95 p-5 backdrop-blur transition-transform lg:static lg:translate-x-0", mobileNavOpen ? "translate-x-0" : "-translate-x-full")}>
        <div className="mb-8 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="grid size-10 place-items-center rounded-xl border border-cyan-300/25 bg-cyan-300/10 text-cyan-200"><ScanLine className="size-5" /></div>
            <div><div className="text-xl font-extrabold tracking-tight">nexa<span className="text-cyan-300">IQ</span></div><div className="text-xs text-slate-500">Repair Intelligence</div></div>
          </div>
          <button className="lg:hidden" onClick={() => setMobileNavOpen(false)} aria-label="Close navigation"><X /></button>
        </div>

        <nav className="space-y-1" aria-label="Primary navigation">
          {navigation.map(([label, Icon], index) => (
            <button key={label} className={cn("flex min-h-11 w-full items-center gap-3 rounded-lg px-3 text-left text-sm font-medium transition", index === 0 ? "bg-cyan-300/10 text-cyan-100" : "text-slate-400 hover:bg-white/5 hover:text-white")}>
              <Icon className="size-4" />{label}{label === "Critical reviews" && <span className="ml-auto rounded-full bg-amber-300 px-2 py-0.5 text-xs font-bold text-slate-950">1</span>}
            </button>
          ))}
        </nav>

        <div className="mt-8 border-t border-white/8 pt-5">
          <p className="mb-2 px-3 text-xs font-bold uppercase tracking-[.16em] text-slate-600">Workspace</p>
          <button className="flex min-h-11 w-full items-center gap-3 rounded-lg px-3 text-sm text-slate-400 hover:bg-white/5 hover:text-white"><Building2 className="size-4" />Locations</button>
          <button className="flex min-h-11 w-full items-center gap-3 rounded-lg px-3 text-sm text-slate-400 hover:bg-white/5 hover:text-white"><Users className="size-4" />Team & access</button>
          <button className="flex min-h-11 w-full items-center gap-3 rounded-lg px-3 text-sm text-slate-400 hover:bg-white/5 hover:text-white"><Settings className="size-4" />Settings</button>
        </div>

        <div className="absolute inset-x-5 bottom-5 rounded-xl border border-cyan-300/15 bg-cyan-300/5 p-4">
          <div className="mb-1 flex items-center gap-2 text-sm font-semibold text-cyan-100"><CircleDot className="size-3 fill-cyan-300 text-cyan-300" /> nexaIQ Beta</div>
          <p className="text-xs leading-relaxed text-slate-400">AI-assisted findings require professional review.</p>
        </div>
      </aside>

      {mobileNavOpen && <button className="fixed inset-0 z-20 bg-black/60 lg:hidden" onClick={() => setMobileNavOpen(false)} aria-label="Close navigation overlay" />}

      <main className="min-w-0">
        <header className="flex h-18 items-center justify-between border-b border-white/8 bg-[#09131d]/80 px-4 backdrop-blur sm:px-7">
          <div className="flex items-center gap-3">
            <button className="rounded-lg p-2 hover:bg-white/5 lg:hidden" onClick={() => setMobileNavOpen(true)} aria-label="Open navigation"><Menu /></button>
            <div><p className="text-xs font-bold uppercase tracking-[.16em] text-cyan-300">{organizationName}</p><h1 className="text-xl font-bold sm:text-2xl">Operations overview</h1></div>
          </div>
          <div className="flex items-center gap-2">
            <button className="hidden min-h-10 items-center gap-2 rounded-lg border border-white/8 bg-white/3 px-3 text-sm text-slate-300 sm:flex"><Search className="size-4" />Search ROs <kbd className="ml-5 text-xs text-slate-600">⌘ K</kbd></button>
            <button className="relative rounded-lg p-2.5 text-slate-400 hover:bg-white/5 hover:text-white" aria-label="Notifications"><Bell className="size-5" /><span className="absolute right-2 top-2 size-2 rounded-full bg-cyan-300" /></button>
            <button className="flex items-center gap-2 rounded-lg p-1.5 hover:bg-white/5"><span className="grid size-8 place-items-center rounded-lg bg-slate-700 text-xs font-bold">SJ</span><ChevronDown className="size-4 text-slate-500" /></button>
          </div>
        </header>

        <div className="mx-auto max-w-[1500px] space-y-6 p-4 sm:p-7">
          <div className="flex flex-col justify-between gap-4 xl:flex-row xl:items-end">
            <div><p className="text-sm text-slate-400">Thursday, September 3</p><h2 className="mt-1 text-2xl font-bold sm:text-3xl">Good evening, Sarah.</h2><p className="mt-1 text-sm text-slate-500">One critical checkpoint needs qualified review.</p></div>
            <input ref={uploadRef} className="hidden" type="file" accept="application/pdf,.pdf" onChange={(event) => void uploadEstimate(event.target.files?.[0])} />
            <Button size="lg" onClick={() => uploadRef.current?.click()} disabled={uploadState === "uploading" || !repairOrderId}><Upload className="size-4" />{uploadState === "uploading" ? "Validating estimate…" : "Import estimate PDF"}</Button>
          </div>

          {uploadState !== "idle" && (
            <div className={cn("flex items-center justify-between rounded-xl border px-4 py-3 text-sm", uploadState === "done" ? "border-emerald-300/25 bg-emerald-300/8 text-emerald-100" : uploadState === "error" ? "border-amber-300/25 bg-amber-300/8 text-amber-100" : "border-cyan-300/20 bg-cyan-300/5 text-cyan-100")}>
              <span>{uploadState === "done" ? `${fileName} preserved and parsed. Human verification required.` : uploadState === "error" ? (repairOrderId ? `${fileName} could not be processed. Confirm the API is running and retry.` : "No repair order is available for this workspace.") : `Checking ${fileName} type, size, and content…`}</span>
              <button onClick={() => setUploadState("idle")} aria-label="Dismiss message"><X className="size-4" /></button>
            </div>
          )}

          <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4" aria-label="Repair workflow summary">
            {([
              ["Open repairs", "18", "+3 this week", Wrench, "cyan"],
              ["Supplement reviews", "6", "2 new candidates", FileSearch, "amber"],
              ["Critical reviews", "1", "Qualified review required", AlertTriangle, "rose"],
              ["Estimate sync", "17 / 18", "1 source verification", Gauge, "green"],
            ] as const).map(([label, value, detail, Icon, tone]) => (
              <Card key={String(label)} className="p-5">
                <div className="flex items-start justify-between"><p className="text-sm font-medium text-slate-400">{String(label)}</p><span className={cn("grid size-9 place-items-center rounded-lg", tone === "cyan" && "bg-cyan-300/10 text-cyan-200", tone === "amber" && "bg-amber-300/10 text-amber-200", tone === "rose" && "bg-rose-300/10 text-rose-200", tone === "green" && "bg-emerald-300/10 text-emerald-200")}><Icon className="size-4" /></span></div>
                <p className="mt-4 text-3xl font-extrabold tracking-tight">{String(value)}</p><p className="mt-1 text-xs text-slate-500">{String(detail)}</p>
              </Card>
            ))}
          </section>

          <section className="grid gap-6 xl:grid-cols-[1.55fr_.85fr]">
            <Card className="overflow-hidden">
              <CardHeader><div><h3 className="font-bold">Recent repair orders</h3><p className="mt-1 text-sm text-slate-500">Work requiring action or recently updated</p></div><Button variant="ghost" size="sm">View all <ArrowUpRight className="size-4" /></Button></CardHeader>
              <div className="overflow-x-auto">
                <table className="w-full min-w-[760px] text-left text-sm">
                  <thead className="border-b border-white/7 text-xs uppercase tracking-wider text-slate-600"><tr>{["RO", "Vehicle", "Estimator", "Estimate", "Workflow status", "Updated", ""].map((heading) => <th className="px-5 py-3 font-semibold" key={heading}>{heading}</th>)}</tr></thead>
                  <tbody>{repairOrders.map((item) => <tr className="border-b border-white/5 transition hover:bg-white/[.025]" key={item.ro}><td className="px-5 py-4 font-bold text-cyan-200">#{item.ro}</td><td className="px-5 py-4 font-semibold">{item.vehicle}</td><td className="px-5 py-4 text-slate-400">{item.estimator}</td><td className="px-5 py-4 text-slate-400">{item.estimate}</td><td className="px-5 py-4"><Badge variant={item.tone}>{item.status}</Badge></td><td className="px-5 py-4 text-slate-500">{item.updated}</td><td className="px-5 py-4"><button aria-label={`Actions for repair order ${item.ro}`}><MoreHorizontal className="size-4 text-slate-500" /></button></td></tr>)}</tbody>
                </table>
              </div>
            </Card>

            <Card>
              <CardHeader><div><div className="mb-2 flex items-center gap-2"><Badge variant="amber">Estimator review required</Badge><span className="text-xs text-slate-600">AI confidence 81%</span></div><h3 className="text-lg font-bold">Possible RH radar bracket deformation</h3><p className="mt-1 text-sm text-slate-500">RO #18472 · 2025 Toyota RAV4</p></div></CardHeader>
              <CardContent className="space-y-5">
                <div className="rounded-xl border border-white/7 bg-black/15 p-4"><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Structured rationale</p><p className="mt-2 text-sm leading-relaxed text-slate-300">Mounting geometry appears inconsistent across two teardown images. Area is partly obscured; physical confirmation is required.</p></div>
                <div className="space-y-2 text-sm"><div className="flex justify-between"><span className="text-slate-500">Estimate comparison</span><span>Possible omission</span></div><div className="flex justify-between"><span className="text-slate-500">Evidence</span><button className="text-cyan-200 hover:underline">2 original photos</button></div><div className="flex justify-between"><span className="text-slate-500">Source quality</span><span>Camera only</span></div></div>
                {candidate === "pending" ? <div className="grid grid-cols-2 gap-2"><Button onClick={() => setCandidate("confirmed")}><Check className="size-4" />Confirm</Button><Button variant="secondary" onClick={() => setCandidate("review")}><AlertTriangle className="size-4" />Needs review</Button><Button className="col-span-2" variant="ghost" onClick={() => setCandidate("dismissed")}>Dismiss candidate</Button></div> : <div className="rounded-xl border border-white/8 bg-white/3 p-4"><div className="flex items-center gap-2 font-semibold"><ClipboardCheck className="size-4 text-cyan-200" />Decision recorded: {candidate.replace("_", " ")}</div><p className="mt-1 text-xs text-slate-500">A production action would require authenticated identity, reason, and an audit event.</p><Button className="mt-3" size="sm" variant="secondary" onClick={() => setCandidate("pending")}>Reset demo</Button></div>}
              </CardContent>
            </Card>
          </section>

          <section className="grid gap-6 lg:grid-cols-3">
            <Card className="lg:col-span-2"><CardHeader><div><h3 className="font-bold">Workflow documentation</h3><p className="mt-1 text-sm text-slate-500">Percentages describe records—not physical vehicle safety.</p></div></CardHeader><CardContent className="grid gap-5 sm:grid-cols-3">{[["Repair workflow",96,"documented"],["Claim documentation",88,"complete"],["Professional sign-off",42,"pending"]].map(([label, value, suffix]) => <div key={String(label)}><div className="mb-2 flex items-center justify-between text-sm"><span className="text-slate-400">{label}</span><span className="font-bold">{value}%</span></div><div className="h-2 overflow-hidden rounded-full bg-white/7"><div className="h-full rounded-full bg-cyan-300" style={{width:`${value}%`}} /></div><p className="mt-2 text-xs text-slate-600">{value}% {suffix}</p></div>)}</CardContent></Card>
            <Card className="border-cyan-300/15 bg-gradient-to-br from-cyan-300/8 to-transparent p-5"><div className="flex items-center gap-3"><span className="grid size-10 place-items-center rounded-xl bg-cyan-300/10"><ShieldCheck className="size-5 text-cyan-200" /></span><div><h3 className="font-bold">Human control active</h3><p className="text-xs text-slate-500">No hidden AI actions</p></div></div><p className="mt-4 text-sm leading-relaxed text-slate-400">Estimate changes, supplements, QC, and sign-offs remain intentional human actions with audit history.</p></Card>
          </section>
        </div>
      </main>
    </div>
  );
}
