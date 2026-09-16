export type OrganizationContext = { id: string; name: string };

export type RepairOrder = {
  id: string;
  ro_number: string;
  workflow_status: string;
  updated_at: string;
  vehicle: { year: number | null; make: string | null; model: string | null; vin: string | null } | null;
};

export type CaptureKind = "photo" | "voice_note";

export type PrivacyFlags = {
  may_contain_face: boolean;
  may_contain_licence_plate: boolean;
  may_contain_customer_document: boolean;
  precise_location_collected: false;
};

export type CaptureQueueItem = {
  id: string;
  clientSessionId: string;
  organizationId: string;
  repairOrderId: string;
  captureKind: CaptureKind;
  sequenceNumber: number;
  localUri: string;
  filename: string;
  mimeType: string;
  capturedAt: string;
  privacyFlags: PrivacyFlags;
  originalMetadata: Record<string, string | number | boolean | null>;
  status: "queued" | "uploading" | "failed";
  attemptCount: number;
  nextAttemptAt: string;
  lastError: string | null;
};
