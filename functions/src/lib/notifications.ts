import { getMessaging } from "firebase-admin/messaging";
import { COL } from "../config/collections";
import type { NotificationCategory } from "../domain/types";
import { localDateKey } from "../domain/time";
import { db, serverTs, Timestamp } from "./firestore";

export interface NotificationJobInput {
  uid: string;
  campusId: string;
  category: NotificationCategory;
  title: string;
  body: string;
  /** deep link route e.g. /events/{id} */
  route?: string;
  data?: Record<string, string>;
  scheduledFor?: Date;
  /** dedupe key — a second job with the same key is ignored */
  dedupeKey: string;
  createdBy?: string;
}

/**
 * Enqueue a notification job. Jobs are processed by `processNotificationJobs`
 * (scheduled) so delivery does not depend on the app being open. Idempotent by
 * `dedupeKey`.
 */
export async function enqueueNotification(input: NotificationJobInput): Promise<"queued" | "duplicate"> {
  const ref = db.collection(COL.notificationJobs).doc(input.dedupeKey.replace(/[/]/g, "_"));
  const existing = await ref.get();
  if (existing.exists) return "duplicate";
  await ref.set({
    ...input,
    route: input.route ?? null,
    data: input.data ?? {},
    scheduledFor: Timestamp.fromDate(input.scheduledFor ?? new Date()),
    status: "pending",
    attempts: 0,
    createdAt: serverTs(),
  });
  return "queued";
}

export async function cancelNotificationsByPrefix(prefix: string): Promise<number> {
  const snap = await db
    .collection(COL.notificationJobs)
    .where("status", "==", "pending")
    .orderBy("__name__")
    .startAt(prefix.replace(/[/]/g, "_"))
    .endAt(prefix.replace(/[/]/g, "_") + "")
    .get();
  const b = db.batch();
  snap.docs.forEach((d) => b.update(d.ref, { status: "cancelled", cancelledAt: serverTs() }));
  await b.commit();
  return snap.size;
}

export interface DeliveryDecision {
  send: boolean;
  reason?: "prefs_disabled" | "cap_exceeded" | "no_tokens" | "user_inactive";
}

/**
 * Notification preference + cap enforcement. Transactional/security alerts bypass
 * the promotional cap; engagement is limited to `capPerDay` per user per campus day.
 */
export async function decideDelivery(
  uid: string,
  category: NotificationCategory,
  campusTz: string,
  capPerDay: number,
): Promise<DeliveryDecision & { tokens: string[] }> {
  const userSnap = await db.collection(COL.users).doc(uid).get();
  if (!userSnap.exists || userSnap.get("status") !== "active") return { send: false, reason: "user_inactive", tokens: [] };
  const prefs = userSnap.get("notificationPrefs") ?? {};
  const prefKey = { transactional: "transactional", reminder: "reminders", engagement: "engagement", post_event: "postEvent" }[category];
  if (category !== "transactional" && prefs[prefKey] === false) return { send: false, reason: "prefs_disabled", tokens: [] };
  const tokens: string[] = Array.isArray(userSnap.get("fcmTokens")) ? userSnap.get("fcmTokens") : [];
  if (category === "engagement") {
    const dayKey = localDateKey(new Date(), campusTz);
    const sentToday = await db
      .collection(COL.notificationDeliveryLogs)
      .where("uid", "==", uid)
      .where("category", "==", "engagement")
      .where("dayKey", "==", dayKey)
      .where("status", "==", "sent")
      .count()
      .get();
    if (sentToday.data().count >= capPerDay) return { send: false, reason: "cap_exceeded", tokens };
  }
  if (tokens.length === 0) return { send: false, reason: "no_tokens", tokens };
  return { send: true, tokens };
}

export async function sendPush(
  tokens: string[],
  payload: { title: string; body: string; route?: string | null; data?: Record<string, string> },
): Promise<{ success: number; failure: number; invalidTokens: string[] }> {
  if (tokens.length === 0) return { success: 0, failure: 0, invalidTokens: [] };
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    // No FCM in the emulator — log and treat as delivered so flows are testable.
    console.log("[emulator] push", payload.title, "→", tokens.length, "tokens");
    return { success: tokens.length, failure: 0, invalidTokens: [] };
  }
  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: payload.title, body: payload.body },
    data: { ...(payload.data ?? {}), route: payload.route ?? "" },
    android: { priority: "high" },
    apns: { payload: { aps: { sound: "default" } } },
  });
  const invalidTokens: string[] = [];
  res.responses.forEach((r, i) => {
    const code = r.error?.code ?? "";
    if (!r.success && (code.includes("registration-token-not-registered") || code.includes("invalid-argument"))) {
      invalidTokens.push(tokens[i]);
    }
  });
  return { success: res.successCount, failure: res.failureCount, invalidTokens };
}
