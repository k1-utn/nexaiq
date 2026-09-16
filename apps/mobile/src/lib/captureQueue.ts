import type { Session } from "@supabase/supabase-js";
import { randomUUID } from "expo-crypto";
import { Directory, File, Paths, UploadType } from "expo-file-system";
import { Platform } from "react-native";

import { supabase } from "./supabase";
import type { CaptureKind, CaptureQueueItem, PrivacyFlags } from "../types";

const QUEUE_KEY = "nexaiq.stage3.capture-queue.v1";
const API_URL = (process.env.EXPO_PUBLIC_API_URL ?? "").replace(/\/$/, "");
let synchronizationTail: Promise<unknown> = Promise.resolve();

export function readCaptureQueue(): CaptureQueueItem[] {
  const raw = localStorage.getItem(QUEUE_KEY);
  if (!raw) return [];
  try {
    const value: unknown = JSON.parse(raw);
    return Array.isArray(value) ? (value as CaptureQueueItem[]) : [];
  } catch {
    return [];
  }
}

export function writeCaptureQueue(items: CaptureQueueItem[]): void {
  localStorage.setItem(QUEUE_KEY, JSON.stringify(items));
}

export async function enqueueCapture(input: {
  sourceUri: string;
  extension: string;
  mimeType: string;
  captureKind: CaptureKind;
  clientSessionId: string;
  organizationId: string;
  repairOrderId: string;
  sequenceNumber: number;
  capturedAt: string;
  privacyFlags: PrivacyFlags;
  originalMetadata: Record<string, string | number | boolean | null>;
}): Promise<CaptureQueueItem> {
  if (Platform.OS === "web") {
    throw new Error("Durable evidence capture is available in Expo Go on a phone.");
  }
  const captureDirectory = new Directory(Paths.document, "nexaiq-captures");
  captureDirectory.create({ idempotent: true, intermediates: true });
  const id = randomUUID();
  const filename = `${input.captureKind}-${id}.${input.extension.replace(/^\./, "")}`;
  const source = new File(input.sourceUri);
  const destination = new File(captureDirectory, filename);
  await source.copy(destination);
  const item: CaptureQueueItem = {
    id, clientSessionId: input.clientSessionId, organizationId: input.organizationId,
    repairOrderId: input.repairOrderId, captureKind: input.captureKind,
    sequenceNumber: input.sequenceNumber, localUri: destination.uri, filename,
    mimeType: input.mimeType, capturedAt: input.capturedAt, privacyFlags: input.privacyFlags,
    originalMetadata: input.originalMetadata, status: "queued", attemptCount: 0,
    nextAttemptAt: new Date(0).toISOString(), lastError: null,
  };
  writeCaptureQueue([...readCaptureQueue(), item]);
  return item;
}

export function synchronizeCaptureQueue(session: Session, organizationId: string, onChange?: (items: CaptureQueueItem[]) => void): Promise<CaptureQueueItem[]> {
  const synchronization = synchronizationTail
    .catch(() => undefined)
    .then(() => synchronizeCaptureQueueNow(session, organizationId, onChange));
  synchronizationTail = synchronization;
  return synchronization;
}

async function captureIsPersisted(item: CaptureQueueItem): Promise<boolean> {
  const { data, error } = await supabase
    .from("scan_session_media")
    .select("id")
    .eq("organization_id", item.organizationId)
    .eq("client_capture_id", item.id)
    .maybeSingle();
  return !error && Boolean(data);
}

async function synchronizeCaptureQueueNow(session: Session, organizationId: string, onChange?: (items: CaptureQueueItem[]) => void): Promise<CaptureQueueItem[]> {
  let queue = readCaptureQueue();
  if (!API_URL) return queue;
  for (const queuedItem of [...queue]) {
    const item = queue.find((candidate) => candidate.id === queuedItem.id);
    if (!item || item.organizationId !== organizationId || Date.parse(item.nextAttemptAt) > Date.now()) continue;
    item.status = "uploading";
    item.lastError = null;
    writeCaptureQueue(queue);
    onChange?.([...queue]);
    try {
      const file = new File(item.localUri);
      if (!file.exists) {
        if (await captureIsPersisted(item)) {
          queue = queue.filter((candidate) => candidate.id !== item.id);
          writeCaptureQueue(queue);
          onChange?.([...queue]);
          continue;
        }
        throw new Error("Local capture is no longer available and no uploaded copy was found");
      }
      const response = await file.upload(`${API_URL}/v1/evidence/captures`, {
        httpMethod: "POST",
        uploadType: UploadType.MULTIPART,
        fieldName: "file",
        mimeType: item.mimeType,
        sessionType: "foreground",
        headers: { Authorization: `Bearer ${session.access_token}`, "X-NexaIQ-Organization-ID": item.organizationId },
        parameters: {
          repair_order_id: item.repairOrderId,
          client_session_id: item.clientSessionId,
          client_capture_id: item.id,
          capture_kind: item.captureKind,
          sequence_number: String(item.sequenceNumber),
          captured_at: item.capturedAt,
          privacy_flags: JSON.stringify(item.privacyFlags),
          original_metadata: JSON.stringify(item.originalMetadata),
        },
      });
      if (response.status < 200 || response.status >= 300) {
        let body: { detail?: string } | null = null;
        try { body = JSON.parse(response.body) as { detail?: string }; } catch { /* Non-JSON API error. */ }
        throw new Error(body?.detail ?? `Upload failed (${response.status})`);
      }
      try { file.delete(); } catch { /* Server copy is already durable. */ }
      queue = queue.filter((candidate) => candidate.id !== item.id);
    } catch (error) {
      const current = queue.find((candidate) => candidate.id === item.id);
      if (current) {
        current.attemptCount += 1;
        current.status = "failed";
        current.lastError = error instanceof Error ? error.message : "Upload failed";
        const delaySeconds = Math.min(300, 2 ** Math.min(current.attemptCount, 8));
        current.nextAttemptAt = new Date(Date.now() + delaySeconds * 1000).toISOString();
      }
    }
    writeCaptureQueue(queue);
    onChange?.([...queue]);
  }
  return queue;
}

export function retryAllCaptures(): CaptureQueueItem[] {
  const queue = readCaptureQueue().map((item) => ({ ...item, status: "queued" as const, nextAttemptAt: new Date(0).toISOString(), lastError: null }));
  writeCaptureQueue(queue);
  return queue;
}
