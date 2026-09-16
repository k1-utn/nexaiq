import NetInfo from "@react-native-community/netinfo";
import type { Session } from "@supabase/supabase-js";
import { RecordingPresets, requestRecordingPermissionsAsync, setAudioModeAsync, useAudioRecorder, useAudioRecorderState } from "expo-audio";
import { CameraView, useCameraPermissions } from "expo-camera";
import { randomUUID } from "expo-crypto";
import { ImageManipulator, SaveFormat } from "expo-image-manipulator";
import { useEffect, useMemo, useRef, useState } from "react";
import { ActivityIndicator, Alert, Image, Platform, ScrollView, StyleSheet, Switch, Text, TouchableOpacity, View } from "react-native";

import { enqueueCapture, readCaptureQueue, retryAllCaptures, synchronizeCaptureQueue } from "../lib/captureQueue";
import type { CaptureQueueItem, OrganizationContext, PrivacyFlags, RepairOrder } from "../types";

export function ScanCaptureScreen({ repairOrder, organization, session, onBack }: { repairOrder: RepairOrder; organization: OrganizationContext; session: Session; onBack: () => void }) {
  const cameraRef = useRef<CameraView>(null);
  const [cameraPermission, requestCameraPermission] = useCameraPermissions();
  const recorder = useAudioRecorder(RecordingPresets.HIGH_QUALITY);
  const recorderState = useAudioRecorderState(recorder, 250);
  const clientSessionId = useMemo(() => randomUUID(), []);
  const nextSequenceRef = useRef(0);
  const [cameraReady, setCameraReady] = useState(false);
  const [cameraOpen, setCameraOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [online, setOnline] = useState<boolean | null>(null);
  const [queue, setQueue] = useState<CaptureQueueItem[]>(() => readCaptureQueue());
  const [privacyFlags, setPrivacyFlags] = useState<PrivacyFlags>({ may_contain_face: false, may_contain_licence_plate: false, may_contain_customer_document: false, precise_location_collected: false });
  const repairQueue = queue.filter((item) => item.repairOrderId === repairOrder.id);
  const vehicle = [repairOrder.vehicle?.year, repairOrder.vehicle?.make, repairOrder.vehicle?.model].filter(Boolean).join(" ");

  useEffect(() => {
    const subscription = NetInfo.addEventListener((state) => {
      const connected = Boolean(state.isConnected && state.isInternetReachable !== false);
      setOnline(connected);
      if (connected) void synchronizeCaptureQueue(session, organization.id, setQueue);
    });
    return () => subscription();
  }, [organization.id, session]);

  function nextSequence(): number {
    const sequence = nextSequenceRef.current;
    nextSequenceRef.current += 1;
    return sequence;
  }

  async function takePhoto() {
    if (!cameraPermission?.granted) {
      const permission = await requestCameraPermission();
      if (!permission.granted) {
        Alert.alert("Camera permission needed", "nexaIQ only opens the camera when you choose to capture repair evidence.");
        return;
      }
    }
    if (!cameraOpen) {
      setCameraOpen(true);
      return;
    }
    if (!cameraReady || !cameraRef.current || busy) return;
    setBusy(true);
    try {
      const photo = await cameraRef.current.takePictureAsync({ quality: .92, exif: false });
      const context = ImageManipulator.manipulate(photo.uri);
      context.resize({ width: 2048, height: null });
      const rendered = await context.renderAsync();
      const compressed = await rendered.saveAsync({ format: SaveFormat.JPEG, compress: .78 });
      const item = await enqueueCapture({
        sourceUri: compressed.uri, extension: "jpg", mimeType: "image/jpeg", captureKind: "photo",
        clientSessionId, organizationId: organization.id, repairOrderId: repairOrder.id,
        sequenceNumber: nextSequence(), capturedAt: new Date().toISOString(), privacyFlags,
        originalMetadata: { width: compressed.width, height: compressed.height, compression_quality: .78, location_collected: false },
      });
      setQueue(readCaptureQueue());
      setCameraOpen(false);
      if (online) void synchronizeCaptureQueue(session, organization.id, setQueue);
      Alert.alert("Photo queued", `Capture ${item.sequenceNumber + 1} is saved on this device until upload completes.`);
    } catch (error) {
      Alert.alert("Photo not saved", error instanceof Error ? error.message : "Capture failed");
    } finally {
      setBusy(false);
    }
  }

  async function toggleVoiceRecording() {
    if (busy) return;
    setBusy(true);
    try {
      if (recorderState.isRecording) {
        const durationMillis = recorderState.durationMillis;
        await recorder.stop();
        const uri = recorder.uri;
        if (!uri) throw new Error("No recording file was created.");
        const web = Platform.OS === "web";
        const item = await enqueueCapture({
          sourceUri: uri, extension: web ? "webm" : "m4a", mimeType: web ? "audio/webm" : "audio/mp4", captureKind: "voice_note",
          clientSessionId, organizationId: organization.id, repairOrderId: repairOrder.id,
          sequenceNumber: nextSequence(), capturedAt: new Date().toISOString(), privacyFlags,
          originalMetadata: { duration_ms: durationMillis, background_recording: false, location_collected: false },
        });
        setQueue(readCaptureQueue());
        if (online) void synchronizeCaptureQueue(session, organization.id, setQueue);
        Alert.alert("Voice note queued", `Observation ${item.sequenceNumber + 1} is saved on this device until upload completes.`);
        return;
      }
      const permission = await requestRecordingPermissionsAsync();
      if (!permission.granted) {
        Alert.alert("Microphone permission needed", "Voice notes are optional and recording starts only after you tap Record.");
        return;
      }
      await setAudioModeAsync({ allowsRecording: true, playsInSilentMode: true, allowsBackgroundRecording: false });
      await recorder.prepareToRecordAsync();
      recorder.record();
    } catch (error) {
      Alert.alert("Voice note not saved", error instanceof Error ? error.message : "Recording failed");
    } finally {
      setBusy(false);
    }
  }

  async function retryNow() {
    setQueue(retryAllCaptures());
    if (!online) {
      Alert.alert("Still offline", "Your captures remain safely queued on this device.");
      return;
    }
    setQueue(await synchronizeCaptureQueue(session, organization.id, setQueue));
  }

  if (cameraOpen) {
    return <View style={styles.cameraPage}><CameraView ref={cameraRef} style={StyleSheet.absoluteFill} facing="back" onCameraReady={() => setCameraReady(true)} /><View style={styles.cameraHeader}><TouchableOpacity onPress={() => setCameraOpen(false)}><Text style={styles.cameraAction}>CANCEL</Text></TouchableOpacity><Text style={styles.cameraLabel}>RO #{repairOrder.ro_number}</Text></View><View style={styles.cameraHint}><Text style={styles.cameraHintText}>Avoid faces, licence plates, and customer paperwork when they are not needed.</Text></View><TouchableOpacity disabled={!cameraReady || busy} onPress={() => void takePhoto()} style={styles.shutter}><View style={styles.shutterInner}>{busy ? <ActivityIndicator color="#071018" /> : null}</View></TouchableOpacity></View>;
  }

  return (
    <ScrollView contentContainerStyle={styles.page}>
      <View style={styles.topRow}><TouchableOpacity onPress={onBack}><Text style={styles.back}>‹ REPAIR ORDERS</Text></TouchableOpacity><View style={[styles.networkBadge, online ? styles.online : styles.offline]}><Text style={styles.networkText}>{online === null ? "CHECKING" : online ? "ONLINE" : "OFFLINE"}</Text></View></View>
      <Text style={styles.eyebrow}>SUPPLEMENT TEARDOWN</Text><Text style={styles.title}>RO #{repairOrder.ro_number}</Text><Text style={styles.vehicle}>{vehicle || "Vehicle details pending"}</Text>
      <View style={styles.privacyCard}><Text style={styles.cardTitle}>Privacy minimization</Text><Text style={styles.cardBody}>Precise location is never collected. Flag unavoidable personal information so it can be reviewed before future AI processing.</Text><PrivacyToggle label="Face may be visible" value={privacyFlags.may_contain_face} onChange={(value) => setPrivacyFlags((flags) => ({ ...flags, may_contain_face: value }))} /><PrivacyToggle label="Licence plate may be visible" value={privacyFlags.may_contain_licence_plate} onChange={(value) => setPrivacyFlags((flags) => ({ ...flags, may_contain_licence_plate: value }))} /><PrivacyToggle label="Customer document may be visible" value={privacyFlags.may_contain_customer_document} onChange={(value) => setPrivacyFlags((flags) => ({ ...flags, may_contain_customer_document: value }))} /></View>
      <TouchableOpacity onPress={() => void takePhoto()} style={styles.primary}><Text style={styles.primaryIcon}>⌗</Text><View><Text style={styles.primaryText}>CAPTURE PHOTO</Text><Text style={styles.primarySub}>Compressed locally · original metadata minimized</Text></View></TouchableOpacity>
      <TouchableOpacity disabled={busy} onPress={() => void toggleVoiceRecording()} style={[styles.secondary, recorderState.isRecording && styles.recording]}><Text style={styles.secondaryIcon}>{recorderState.isRecording ? "■" : "●"}</Text><View><Text style={styles.secondaryText}>{recorderState.isRecording ? "STOP VOICE NOTE" : "OPTIONAL VOICE NOTE"}</Text><Text style={styles.secondarySub}>{recorderState.isRecording ? `${Math.ceil(recorderState.durationMillis / 1000)} seconds` : "Tap once to record, then again to save"}</Text></View></TouchableOpacity>
      <View style={styles.queueCard}><View style={styles.queueHeader}><View><Text style={styles.cardTitle}>Upload queue</Text><Text style={styles.cardBody}>{repairQueue.length ? `${repairQueue.length} capture${repairQueue.length === 1 ? "" : "s"} waiting or retrying` : "All captures uploaded"}</Text></View>{repairQueue.length ? <TouchableOpacity onPress={() => void retryNow()}><Text style={styles.retry}>RETRY NOW</Text></TouchableOpacity> : null}</View>{repairQueue.map((item) => <View key={item.id} style={styles.queueRow}>{item.captureKind === "photo" ? <Image source={{ uri: item.localUri }} style={styles.thumbnail} /> : <View style={styles.audioThumb}><Text style={styles.audioIcon}>♪</Text></View>}<View style={styles.queueText}><Text style={styles.queueName}>{item.captureKind === "photo" ? "Teardown photo" : "Voice observation"} #{item.sequenceNumber + 1}</Text><Text style={[styles.queueStatus, item.status === "failed" && styles.failed]}>{item.status === "uploading" ? "Uploading…" : item.status === "failed" ? item.lastError ?? "Retry scheduled" : online ? "Queued for upload" : "Safe on device · waiting for network"}</Text></View></View>)}</View>
      <View style={styles.legalNotice}><Text style={styles.legalTitle}>EVIDENCE, NOT A DECISION</Text><Text style={styles.legalBody}>Camera measurements are approximate. Captures do not certify damage, repair quality, or vehicle safety. Findings require qualified human review.</Text></View>
    </ScrollView>
  );
}

function PrivacyToggle({ label, value, onChange }: { label: string; value: boolean; onChange: (value: boolean) => void }) {
  return <View style={styles.toggleRow}><Text style={styles.toggleLabel}>{label}</Text><Switch value={value} onValueChange={onChange} trackColor={{ false: "#233140", true: "#155e75" }} thumbColor={value ? "#67e8f9" : "#94a3b8"} /></View>;
}

const styles = StyleSheet.create({
  page: { padding: 22, paddingTop: 22, paddingBottom: 50 }, topRow: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: 24 }, back: { color: "#94a3b8", fontSize: 11, fontWeight: "800" },
  networkBadge: { paddingHorizontal: 9, paddingVertical: 5, borderRadius: 99 }, online: { backgroundColor: "rgba(52,211,153,.12)" }, offline: { backgroundColor: "rgba(251,191,36,.12)" }, networkText: { color: "#cbd5e1", fontSize: 9, fontWeight: "900", letterSpacing: 1 },
  eyebrow: { color: "#67e8f9", fontSize: 10, fontWeight: "900", letterSpacing: 1.3 }, title: { color: "#f8fafc", fontSize: 34, fontWeight: "900", marginTop: 5 }, vehicle: { color: "#94a3b8", fontSize: 17, marginTop: 3, marginBottom: 20 },
  privacyCard: { backgroundColor: "#0d1925", borderWidth: 1, borderColor: "rgba(255,255,255,.08)", borderRadius: 16, padding: 17, marginBottom: 14 }, cardTitle: { color: "#e2e8f0", fontSize: 15, fontWeight: "900" }, cardBody: { color: "#64748b", fontSize: 12, lineHeight: 18, marginTop: 4 }, toggleRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", minHeight: 45, borderTopWidth: 1, borderTopColor: "rgba(255,255,255,.06)", marginTop: 10, paddingTop: 8 }, toggleLabel: { color: "#cbd5e1", fontSize: 13 },
  primary: { minHeight: 88, backgroundColor: "#67e8f9", borderRadius: 17, padding: 19, flexDirection: "row", alignItems: "center", marginBottom: 10 }, primaryIcon: { color: "#071018", fontSize: 34, marginRight: 14 }, primaryText: { color: "#071018", fontSize: 16, fontWeight: "900", letterSpacing: .4 }, primarySub: { color: "#155e75", fontSize: 11, marginTop: 4 },
  secondary: { minHeight: 74, backgroundColor: "#0d1925", borderWidth: 1, borderColor: "rgba(255,255,255,.08)", borderRadius: 16, padding: 17, flexDirection: "row", alignItems: "center", marginBottom: 14 }, recording: { borderColor: "rgba(251,113,133,.45)", backgroundColor: "rgba(159,18,57,.16)" }, secondaryIcon: { color: "#fb7185", fontSize: 21, marginRight: 14 }, secondaryText: { color: "#e2e8f0", fontSize: 13, fontWeight: "900" }, secondarySub: { color: "#64748b", fontSize: 11, marginTop: 3 },
  queueCard: { backgroundColor: "#0d1925", borderWidth: 1, borderColor: "rgba(255,255,255,.08)", borderRadius: 16, padding: 17 }, queueHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center" }, retry: { color: "#67e8f9", fontSize: 10, fontWeight: "900" }, queueRow: { flexDirection: "row", alignItems: "center", borderTopWidth: 1, borderTopColor: "rgba(255,255,255,.06)", marginTop: 12, paddingTop: 12 }, thumbnail: { width: 48, height: 48, borderRadius: 9, backgroundColor: "#152330" }, audioThumb: { width: 48, height: 48, borderRadius: 9, backgroundColor: "rgba(251,113,133,.12)", alignItems: "center", justifyContent: "center" }, audioIcon: { color: "#fb7185", fontSize: 22 }, queueText: { flex: 1, marginLeft: 11 }, queueName: { color: "#cbd5e1", fontSize: 12, fontWeight: "800" }, queueStatus: { color: "#64748b", fontSize: 10, marginTop: 3 }, failed: { color: "#fbbf24" },
  legalNotice: { borderLeftWidth: 3, borderLeftColor: "#fbbf24", backgroundColor: "rgba(251,191,36,.06)", padding: 15, marginTop: 15, borderRadius: 4 }, legalTitle: { color: "#fde68a", fontSize: 10, fontWeight: "900", letterSpacing: 1 }, legalBody: { color: "#94a3b8", fontSize: 12, lineHeight: 18, marginTop: 5 },
  cameraPage: { flex: 1, backgroundColor: "#000" }, cameraHeader: { position: "absolute", left: 20, right: 20, top: 52, flexDirection: "row", justifyContent: "space-between" }, cameraAction: { color: "#fff", fontSize: 12, fontWeight: "900" }, cameraLabel: { color: "#fff", fontSize: 12, fontWeight: "800" }, cameraHint: { position: "absolute", left: 20, right: 20, bottom: 145, backgroundColor: "rgba(7,16,24,.78)", padding: 12, borderRadius: 10 }, cameraHintText: { color: "#e2e8f0", fontSize: 12, lineHeight: 17, textAlign: "center" }, shutter: { position: "absolute", bottom: 45, alignSelf: "center", width: 76, height: 76, borderRadius: 38, borderWidth: 5, borderColor: "#fff", alignItems: "center", justifyContent: "center" }, shutterInner: { width: 58, height: 58, borderRadius: 29, backgroundColor: "#fff", alignItems: "center", justifyContent: "center" },
});
