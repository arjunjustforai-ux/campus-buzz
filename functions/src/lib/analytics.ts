import { COL } from "../config/collections";
import { POSTHOG_SERVER_KEY } from "../config/secrets";
import { db, serverTs } from "./firestore";

/**
 * First-party analytics event log. Authoritative metrics are computed from
 * Firestore records, not from this log; this log exists for funnel analysis and
 * for optional forwarding to PostHog when a key is configured.
 */
export async function track(
  event: string,
  props: { uid?: string; campusId?: string; eventId?: string; organizerId?: string; tribeIds?: string[]; role?: string; source?: string; feedVariant?: string; [k: string]: unknown },
): Promise<void> {
  try {
    await db.collection(COL.analyticsEvents).add({ event, ...props, at: serverTs() });
  } catch (e) {
    console.warn("analytics write failed", e);
  }
  const key = safePosthogKey();
  if (key) {
    try {
      await fetch("https://app.posthog.com/capture/", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ api_key: key, event, distinct_id: props.uid ?? "server", properties: props }),
      });
    } catch (e) {
      console.warn("posthog forward failed", e);
    }
  }
}

function safePosthogKey(): string {
  try {
    return process.env.POSTHOG_SERVER_KEY || POSTHOG_SERVER_KEY.value() || "";
  } catch {
    return "";
  }
}
