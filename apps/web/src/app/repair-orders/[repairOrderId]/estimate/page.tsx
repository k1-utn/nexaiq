import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { connection } from "next/server";
import { ArrowLeft, FileWarning } from "lucide-react";
import { EstimateVerification } from "@/components/estimate-verification";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { createClient } from "@/lib/supabase/server";

export default async function EstimatePage({
  params,
}: {
  params: Promise<{ repairOrderId: string }>;
}) {
  await connection();
  const { repairOrderId } = await params;
  const supabase = await createClient();
  const { data: authData } = await supabase.auth.getClaims();
  const reviewerId = authData?.claims?.sub;
  if (!reviewerId) redirect("/login");

  const { data: memberships } = await supabase
    .from("organization_members")
    .select("organization_id")
    .eq("status", "active")
    .limit(1);
  const organizationId = memberships?.[0]?.organization_id;
  if (!organizationId) redirect("/login?error=no_organization");

  const { data: repairOrder } = await supabase
    .from("repair_orders")
    .select("id, ro_number, vehicle_id")
    .eq("id", repairOrderId)
    .eq("organization_id", organizationId)
    .maybeSingle();
  if (!repairOrder) notFound();

  const [{ data: organization }, { data: vehicle }, { data: versions }] = await Promise.all([
    supabase.from("organizations").select("name").eq("id", organizationId).single(),
    supabase.from("vehicles").select("year, make, model, vin").eq("id", repairOrder.vehicle_id).single(),
    supabase
      .from("estimate_versions")
      .select("id, version_number, source_media_id, parse_status, parser_name, parser_version, created_at, verified_at")
      .eq("repair_order_id", repairOrderId)
      .order("version_number", { ascending: false })
      .limit(1),
  ]);

  const estimateVersion = versions?.[0];
  if (!estimateVersion) {
    return (
      <main className="grid-noise min-h-screen px-4 py-10 sm:px-8">
        <div className="mx-auto max-w-3xl">
          <Button asChild variant="ghost"><Link href="/"><ArrowLeft className="size-4" />Back to overview</Link></Button>
          <Card className="mt-8 p-8 text-center">
            <FileWarning className="mx-auto size-10 text-amber-200" />
            <h1 className="mt-4 text-2xl font-bold">No estimate has been imported</h1>
            <p className="mt-2 text-sm text-slate-400">Return to the overview and import the original Mitchell PDF for this repair order.</p>
          </Card>
        </div>
      </main>
    );
  }

  const [{ data: lines }, { data: reviews }, { data: sourceMedia }] = await Promise.all([
    supabase
      .from("estimate_lines")
      .select("id, source_line_number, operation_code, description, amount, raw_text, parse_confidence, line_role")
      .eq("estimate_version_id", estimateVersion.id)
      .order("source_line_number", { ascending: true }),
    supabase
      .from("estimate_line_reviews")
      .select("id, estimate_line_id, reviewer_id, decision, corrected_description, corrected_amount, note, supersedes_review_id, reviewed_at")
      .eq("estimate_version_id", estimateVersion.id)
      .order("reviewed_at", { ascending: true }),
    supabase
      .from("media")
      .select("object_path, original_filename, content_sha256")
      .eq("id", estimateVersion.source_media_id)
      .maybeSingle(),
  ]);

  const { data: signedSource } = sourceMedia
    ? await supabase.storage.from("repair-evidence").createSignedUrl(sourceMedia.object_path, 300)
    : { data: null };

  return (
    <EstimateVerification
      organizationName={organization?.name ?? "Current organization"}
      repairOrder={{
        id: repairOrder.id,
        number: repairOrder.ro_number,
        vehicle: [vehicle?.year, vehicle?.make, vehicle?.model].filter(Boolean).join(" ") || "Vehicle not recorded",
        vin: vehicle?.vin ?? null,
      }}
      estimate={{
        id: estimateVersion.id,
        versionNumber: estimateVersion.version_number,
        parseStatus: estimateVersion.parse_status,
        parserName: estimateVersion.parser_name,
        parserVersion: estimateVersion.parser_version,
        importedAt: estimateVersion.created_at,
        verifiedAt: estimateVersion.verified_at,
        sourceFilename: sourceMedia?.original_filename ?? "Original estimate PDF",
        sourceSha256: sourceMedia?.content_sha256 ?? null,
        sourceUrl: signedSource?.signedUrl ?? null,
      }}
      lines={lines ?? []}
      reviews={reviews ?? []}
      currentReviewerId={reviewerId}
    />
  );
}
