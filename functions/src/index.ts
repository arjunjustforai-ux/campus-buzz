/**
 * CampusBuzz Cloud Functions — server-authoritative domain logic.
 * Every economy-, security- or integrity-sensitive operation lives here.
 */
import { setGlobalOptions } from "firebase-functions/v2";
import { REGION } from "./lib/options";

setGlobalOptions({ region: REGION, maxInstances: 20 });

export * from "./handlers/auth";
export * from "./handlers/events";
export * from "./handlers/rsvp";
export * from "./handlers/checkin";
export * from "./handlers/feedback";
export * from "./handlers/rewards";
export * from "./handlers/friends";
export * from "./handlers/quests";
export * from "./handlers/admin";
export * from "./handlers/metrics";
export * from "./handlers/feed";
export * from "./handlers/surveys";
export * from "./handlers/scheduled";
export * from "./handlers/privacy";
