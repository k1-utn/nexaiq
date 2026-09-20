import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { ArrowLeft, FileCheck2, ShieldCheck } from "lucide-react";
import { SupplementReportActions } from "@/components/supplement-report-actions";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { createClient } from "@/lib/supabase/server";

type EvidenceSnapshot = { media_id?: string; evidence_role?: string; original_filename?: string; content_sha256?: string };
type SourceSnapshot = { component?: string; condition?: string; confidence?: number; source_quality?: string; limitations?: string[] };

export default async function SupplementReportPage({ params }: { params: Promise<{ repairOrderId: string; packageId: string }> }) {
  await connection();
  const { repairOrderId, packageId } = await params;
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getClaims();
  if (!authData?.claims?.sub) redirect("/login");
  const { data: memberships } = await supabase.from("organization_members").select("organization_id").eq("status", "active").limit(1);
  const organizationId = memberships?.[0]?.organization_id;
  if (!organizationId) redirect("/login?error=no_organization");

  const [{ data: reviewPackage }, { data: repairOrder }, { data: organization }, { data: items }] = await Promise.all([
    supabase.from("supplement_review_packages").select("id, package_number, status, approval_note, approval_attestation, approved_by, approved_at, created_at").eq("id", packageId).eq("repair_order_id", repairOrderId).eq("organization_id", organizationId).maybeSingle(),
    supabase.from("repair_orders").select("id, ro_number, vehicle_id").eq("id", repairOrderId).eq("organization_id", organizationId).maybeSingle(),
    supabase.from("organizations").select("name").eq("id", organizationId).single(),
    supabase.from("supplement_review_package_items").select("id, sequence_number, proposed_operation, reason, review_note, oem_consideration_status, oem_source_document_id, oem_source_note, evidence_references, source_snapshot").eq("package_id", packageId).eq("organization_id", organizationId).order("sequence_number"),
  ]);
  if (!reviewPackage || !repairOrder) notFound();

  const { data: vehicle } = await supabase.from("vehicles").select("year, make, model, vin").eq("id", repairOrder.vehicle_id).single();
  const documentIds = [...new Set((items ?? []).map((item) => item.oem_source_document_id).filter((id): id is string => Boolean(id)))];
  const [{ data: documents }, { data: documentSources }] = await Promise.all([
    documentIds.length ? supabase.from("documents").select("id, title, revision, applicability").in("id", documentIds) : Promise.resolve({ data: [] }),
    documentIds.length ? supabase.from("document_sources").select("document_id, source_name, source_locator, section_reference, retrieved_at, content_sha256").in("document_id", documentIds) : Promise.resolve({ data: [] }),
  ]);
  const documentById = new Map((documents ?? []).map((document) => [document.id, document]));
  const sourceByDocumentId = new Map((documentSources ?? []).map((source) => [source.document_id, source]));

  return <main className="report-surface min-h-screen bg-slate-100 px-4 py-8 text-slate-950 sm:px-8">
    <div className="no-print mx-auto mb-5 flex max-w-5xl items-center justify-between gap-3"><Button asChild variant="secondary" className="border-slate-300 bg-white text-slate-800 hover:bg-slate-100"><Link href={`/repair-orders/${repairOrderId}/supplement-review`}><ArrowLeft className="size-4" />Back to review</Link></Button><SupplementReportActions /></div>
    <article className="mx-auto max-w-5xl rounded-xl bg-white p-7 shadow-xl print:max-w-none print:rounded-none print:p-0 print:shadow-none">
      <header className="flex flex-wrap items-start justify-between gap-6 border-b-2 border-slate-900 pb-6"><div><p className="text-sm font-bold uppercase tracking-[.18em] text-cyan-700">nexaIQ · Decision Support</p><h1 className="mt-2 text-3xl font-black">Supplement Review Package</h1><p className="mt-2 text-sm text-slate-600">Estimator-reviewed candidate documentation—not an estimate modification or insurer submission.</p></div><div className="text-right"><p className="text-2xl font-black">#{reviewPackage.package_number}</p><Badge variant={reviewPackage.status === "approved" ? "green" : reviewPackage.status === "changes_requested" ? "rose" : "amber"}>{reviewPackage.status.replaceAll("_", " ")}</Badge></div></header>
      <section className="grid gap-4 border-b border-slate-200 py-6 sm:grid-cols-2"><div><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Organization</p><p className="mt-1 font-bold">{organization?.name ?? "Current organization"}</p><p className="mt-4 text-xs font-bold uppercase tracking-wider text-slate-500">Repair order</p><p className="mt-1 font-bold">#{repairOrder.ro_number}</p></div><div><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Vehicle</p><p className="mt-1 font-bold">{[vehicle?.year, vehicle?.make, vehicle?.model].filter(Boolean).join(" ") || "Not recorded"}</p><p className="mt-1 text-sm text-slate-600">VIN {vehicle?.vin ?? "not recorded"}</p><p className="mt-4 text-xs text-slate-500">Package created {new Date(reviewPackage.created_at).toLocaleString("en-CA")}</p></div></section>
      <section className="space-y-6 py-6">{(items ?? []).map((item) => {
        const source = item.source_snapshot as SourceSnapshot;
        const evidence = Array.isArray(item.evidence_references) ? item.evidence_references as EvidenceSnapshot[] : [];
        const document = item.oem_source_document_id ? documentById.get(item.oem_source_document_id) : null;
        const documentSource = item.oem_source_document_id ? sourceByDocumentId.get(item.oem_source_document_id) : null;
        return <section className="break-inside-avoid rounded-lg border border-slate-300 p-5" key={item.id}><div className="flex items-start justify-between gap-4"><div><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Candidate {item.sequence_number}</p><h2 className="mt-1 text-xl font-black">{item.proposed_operation}</h2><p className="mt-1 text-sm text-slate-600">{[source.component, source.condition].filter(Boolean).join(" · ") || "Condition documented in linked evidence"}</p></div>{source.confidence != null && <span className="text-xs text-slate-500">AI confidence {Math.round(Number(source.confidence) * 100)}%<br />Human reviewed</span>}</div><div className="mt-4 grid gap-4 sm:grid-cols-2"><div><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Reason</p><p className="mt-1 text-sm leading-relaxed">{item.reason}</p>{item.review_note && <><p className="mt-3 text-xs font-bold uppercase tracking-wider text-slate-500">Estimator note</p><p className="mt-1 text-sm">{item.review_note}</p></>}</div><div><p className="text-xs font-bold uppercase tracking-wider text-slate-500">OEM/source consideration</p><p className="mt-1 text-sm font-semibold">{item.oem_consideration_status.replaceAll("_", " ")}</p>{document && <p className="mt-1 text-sm">{document.title}{document.revision ? ` · ${document.revision}` : ""}</p>}{documentSource && <p className="mt-1 text-xs text-slate-600">{[documentSource.source_name, documentSource.section_reference].filter(Boolean).join(" · ")}</p>}{item.oem_source_note && <p className="mt-2 text-sm">{item.oem_source_note}</p>}</div></div><div className="mt-4 border-t border-slate-200 pt-4"><p className="text-xs font-bold uppercase tracking-wider text-slate-500">Evidence references</p>{evidence.length ? <ul className="mt-2 space-y-1 text-xs text-slate-700">{evidence.map((entry, index) => <li key={`${entry.media_id}-${index}`}>{entry.original_filename ?? entry.media_id} · {entry.evidence_role ?? "supporting"} · SHA-256 {entry.content_sha256?.slice(0, 16)}…</li>)}</ul> : <p className="mt-2 text-sm font-semibold text-amber-700">No evidence reference was captured in this package.</p>}</div></section>;
      })}</section>
      {reviewPackage.status === "approved" && <section className="break-inside-avoid border-y-2 border-emerald-700 bg-emerald-50 p-5"><div className="flex items-start gap-3"><FileCheck2 className="mt-0.5 size-5 text-emerald-700" /><div><h2 className="font-black text-emerald-900">Estimator approval recorded</h2><p className="mt-1 text-sm text-emerald-950">{reviewPackage.approval_attestation}</p><p className="mt-2 text-xs text-emerald-800">Approved {reviewPackage.approved_at ? new Date(reviewPackage.approved_at).toLocaleString("en-CA") : ""} · Authentication context stored in the audit history.</p></div></div></section>}
      <footer className="mt-7 flex items-start gap-3 border-t border-slate-300 pt-5 text-xs leading-relaxed text-slate-600"><ShieldCheck className="mt-0.5 size-4 shrink-0" /><p>This report contains possible supplement operations reviewed by a human estimator. It does not certify repair safety, OEM compliance, insurer coverage, or payment. No estimate was modified and no supplement was submitted automatically.</p></footer>
    </article>
  </main>;
}
