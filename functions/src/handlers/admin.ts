import { onCall } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { DEFAULT_ECONOMY, DEFAULT_FEATURE_FLAGS, DEFAULT_PILOT } from "../config/defaults";
import { fail } from "../domain/errors";
import type { EconomyConfig, EntitlementKey, FeatureFlags } from "../domain/types";
import { writeAudit } from "../lib/audit";
import { callableHandler, num, requireAuth, requireMembership, requireSuperAdmin, str, strArray } from "../lib/auth";
import { loadCampus } from "../lib/campus";
import { db, forEachPage, inc, serverTs, Timestamp, toDate } from "../lib/firestore";
import { enqueueNotification } from "../lib/notifications";
import { callableOpts } from "../lib/options";

const ECONOMY_KEYS: Array<keyof EconomyConfig> = ["rsvpReward", "checkinReward", "feedbackReward", "referralReward", "organizerReward", "organizerMinVerifiedAttendees", "streakThresholdWeeks", "streakMultiplier", "coinExpiryDays", "engagementNotificationCapPerDay", "checkinOpensMinutesBefore", "checkinClosesMinutesAfter", "manualCorrectionWindowHours"];

/** Super admin provisions a campus (domains, timezone, defaults). */
export const provisionCampus = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    await requireSuperAdmin(actor);
    const campusId = str(req.data?.campusId, "campusId", { max: 40 }).toLowerCase().replace(/[^a-z0-9-]/g, "-");
    const name = str(req.data?.name, "name", { max: 120 });
    const shortName = str(req.data?.shortName, "shortName", { optional: true, max: 20 }) || name;
    const domains = strArray(req.data?.domains, "domains", { max: 20 }).map((d) => d.toLowerCase());
    const timezone = str(req.data?.timezone, "timezone", { optional: true }) || "Asia/Kolkata";
    try { new Intl.DateTimeFormat("en-US", { timeZone: timezone }); } catch { fail("invalid_argument", "Unknown timezone."); }
    const city = str(req.data?.city, "city", { optional: true, max: 80 });
    const adminUid = str(req.data?.adminUid, "adminUid", { optional: true });
    const ref = db.collection(COL.campuses).doc(campusId);
    await db.runTransaction(async (tx) => {
      const prev = await tx.get(ref);
      tx.set(ref, { name, shortName, domains, timezone, city, status: "active", economy: prev.get("economy") ?? DEFAULT_ECONOMY, pilot: prev.get("pilot") ?? DEFAULT_PILOT, featureFlags: prev.get("featureFlags") ?? DEFAULT_FEATURE_FLAGS, updatedAt: serverTs(), ...(prev.exists ? {} : { createdAt: serverTs(), createdBy: actor.uid }) }, { merge: true });
      if (adminUid) tx.set(db.collection(COL.memberships).doc(ids.membership(campusId, adminUid)), { campusId, uid: adminUid, roles: ["student", "campus_admin"], status: "active", clubIds: [], joinedAt: serverTs() }, { merge: true });
      writeAudit({ actorUid: actor.uid, action: prev.exists ? "campus.update" : "campus.provision", entityType: "campus", entityId: campusId, campusId, before: prev.exists ? { domains: prev.get("domains"), timezone: prev.get("timezone") } : null, after: { domains, timezone, name } }, tx);
    });
    return { campusId };
  }),
);

/** Campus admin edits campus config; economy changes are versioned + audited + optionally announced. */
export const updateCampusConfig = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const campus = await loadCampus(campusId);
    const d = req.data ?? {};
    const update: Record<string, unknown> = { updatedAt: serverTs() };
    const before: Record<string, unknown> = {};
    const after: Record<string, unknown> = {};
    if (d.name) { before.name = campus.name; after.name = update.name = str(d.name, "name", { max: 120 }); }
    if (d.domains) { before.domains = campus.domains; after.domains = update.domains = strArray(d.domains, "domains", { max: 20 }).map((x) => x.toLowerCase()); }
    if (d.timezone) { const tz = str(d.timezone, "timezone"); try { new Intl.DateTimeFormat("en-US", { timeZone: tz }); } catch { fail("invalid_argument", "Unknown timezone."); } before.timezone = campus.timezone; after.timezone = update.timezone = tz; }
    if (d.featureFlags && typeof d.featureFlags === "object") {
      const flags: Partial<FeatureFlags> = {};
      for (const k of Object.keys(DEFAULT_FEATURE_FLAGS) as Array<keyof FeatureFlags>) if (typeof d.featureFlags[k] === "boolean") flags[k] = d.featureFlags[k];
      before.featureFlags = campus.featureFlags; after.featureFlags = update.featureFlags = { ...campus.featureFlags, ...flags };
    }
    if (d.pilot && typeof d.pilot === "object") {
      before.pilot = campus.pilot;
      after.pilot = update.pilot = { targets: { ...campus.pilot.targets, ...(d.pilot.targets ?? {}) }, bands: { ...campus.pilot.bands, ...(d.pilot.bands ?? {}) }, economyHealth: { ...campus.pilot.economyHealth, ...(d.pilot.economyHealth ?? {}) } };
    }
    if (d.privacyPolicyUrl !== undefined) update.privacyPolicyUrl = str(d.privacyPolicyUrl, "privacyPolicyUrl", { optional: true, max: 500 });
    if (d.termsUrl !== undefined) update.termsUrl = str(d.termsUrl, "termsUrl", { optional: true, max: 500 });

    let economyChanged = false;
    if (d.economy && typeof d.economy === "object") {
      const next: EconomyConfig = { ...campus.economy };
      for (const k of ECONOMY_KEYS) if (d.economy[k] !== undefined) (next as unknown as Record<string, number>)[k] = num(d.economy[k], `economy.${k}`, { min: 0, max: 100000 });
      economyChanged = ECONOMY_KEYS.some((k) => next[k] !== campus.economy[k]);
      if (economyChanged) {
        next.version = campus.economy.version + 1;
        next.description = str(d.economy.description, "economy.description", { optional: true, max: 300 }) || `Economy update v${next.version}`;
        const eff = toDate(d.economy.effectiveAt);
        next.effectiveAt = eff ? eff.toISOString() : null;
        before.economy = campus.economy; after.economy = update.economy = next;
      }
    }
    await db.runTransaction(async (tx) => {
      tx.set(db.collection(COL.campuses).doc(campusId), update, { merge: true });
      if (economyChanged) {
        const next = update.economy as EconomyConfig;
        tx.set(db.collection(COL.economyVersions).doc(ids.economyVersion(campusId, next.version)), { campusId, ...next, previous: campus.economy, changedBy: actor.uid, changedAt: serverTs(), noticeSent: !!d.economy?.announce });
      }
      writeAudit({ actorUid: actor.uid, action: economyChanged ? "campus.config.economy" : "campus.config", entityType: "campus", entityId: campusId, campusId, before, after, reason: str(d.reason, "reason", { optional: true, max: 500 }) }, tx);
    });
    if (economyChanged && d.economy?.announce === true) {
      const next = update.economy as EconomyConfig;
      await forEachPage(db.collection(COL.memberships).where("campusId", "==", campusId).where("status", "==", "active"), 300, async (docs) => {
        for (const m of docs) await enqueueNotification({ uid: m.get("uid"), campusId, category: "transactional", title: "BuzzCoin rules are changing", body: next.description, route: "/rewards", dedupeKey: `economy:${campusId}:v${next.version}:${m.get("uid")}` });
      });
    }
    return { ok: true, economyVersion: (update.economy as EconomyConfig | undefined)?.version ?? campus.economy.version };
  }),
);

/** Campus admin manages clubs. */
export const upsertClub = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const clubId = str(req.data?.clubId, "clubId", { optional: true });
    const doc = { campusId, name: str(req.data?.name, "name", { max: 100 }), description: str(req.data?.description, "description", { optional: true, max: 1000 }), category: str(req.data?.category, "category", { optional: true, max: 40 }), logoUrl: str(req.data?.logoUrl, "logoUrl", { optional: true, max: 2000 }) || null, status: (str(req.data?.status, "status", { optional: true }) || "active"), updatedAt: serverTs() };
    const ref = clubId ? db.collection(COL.clubs).doc(clubId) : db.collection(COL.clubs).doc();
    const prev = await ref.get();
    if (prev.exists && prev.get("campusId") !== campusId) fail("permission_denied");
    await ref.set({ ...doc, ...(prev.exists ? {} : { adminUids: [], createdAt: serverTs(), stats: { events: 0 } }) }, { merge: true });
    writeAudit({ actorUid: actor.uid, action: prev.exists ? "club.update" : "club.create", entityType: "club", entityId: ref.id, campusId, after: { name: doc.name, status: doc.status } });
    return { clubId: ref.id };
  }),
);

export const upsertTribe = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const tribeId = str(req.data?.tribeId, "tribeId", { optional: true });
    const doc = { campusId, name: str(req.data?.name, "name", { max: 40 }), emoji: str(req.data?.emoji, "emoji", { optional: true, max: 8 }), color: str(req.data?.color, "color", { optional: true, max: 9 }) || "#FF5F1F", description: str(req.data?.description, "description", { optional: true, max: 200 }), order: num(req.data?.order, "order", { optional: true, int: true, min: 0, max: 999 }), active: req.data?.active !== false, updatedAt: serverTs() };
    const ref = tribeId ? db.collection(COL.tribes).doc(tribeId) : db.collection(COL.tribes).doc();
    const prev = await ref.get();
    if (prev.exists && prev.get("campusId") !== campusId) fail("permission_denied");
    await ref.set({ ...doc, ...(prev.exists ? {} : { createdAt: serverTs() }) }, { merge: true });
    writeAudit({ actorUid: actor.uid, action: "tribe.upsert", entityType: "tribe", entityId: ref.id, campusId, after: { name: doc.name, active: doc.active } });
    return { tribeId: ref.id };
  }),
);

export const upsertVendor = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const vendorId = str(req.data?.vendorId, "vendorId", { optional: true });
    const doc = { campusId, name: str(req.data?.name, "name", { max: 100 }), contact: str(req.data?.contact, "contact", { optional: true, max: 200 }), settlementTerms: str(req.data?.settlementTerms, "settlementTerms", { optional: true, max: 500 }), status: str(req.data?.status, "status", { optional: true }) || "active", updatedAt: serverTs() };
    const ref = vendorId ? db.collection(COL.vendors).doc(vendorId) : db.collection(COL.vendors).doc();
    const prev = await ref.get();
    if (prev.exists && prev.get("campusId") !== campusId) fail("permission_denied");
    await ref.set({ ...doc, ...(prev.exists ? {} : { createdAt: serverTs(), stats: { fulfilled: 0, pendingSettlementValue: 0 } }) }, { merge: true });
    writeAudit({ actorUid: actor.uid, action: "vendor.upsert", entityType: "vendor", entityId: ref.id, campusId, after: { name: doc.name, status: doc.status } });
    return { vendorId: ref.id };
  }),
);

/** Mark a settlement month as settled for a vendor (audited operational record). */
export const settleVendorMonth = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    const vendorId = str(req.data?.vendorId, "vendorId");
    const month = str(req.data?.month, "month", { max: 7 });
    await requireMembership(actor, campusId, ["campus_admin"]);
    const snap = await db.collection(COL.redemptions).where("vendorId", "==", vendorId).where("settlementMonth", "==", month).where("settlementStatus", "==", "pending").get();
    let value = 0;
    const b = db.batch();
    snap.docs.forEach((d) => { value += Number(d.get("faceValue") ?? 0); b.update(d.ref, { settlementStatus: "settled", settledAt: serverTs(), settledBy: actor.uid }); });
    b.set(db.collection(COL.vendors).doc(vendorId), { [`settlements.${month}`]: { count: snap.size, value, settledAt: serverTs() }, "stats.pendingSettlementValue": inc(-value) }, { merge: true });
    await b.commit();
    writeAudit({ actorUid: actor.uid, action: "vendor.settle", entityType: "vendor", entityId: vendorId, campusId, after: { month, count: snap.size, value } });
    return { count: snap.size, value };
  }),
);

/** Entitlements: super admin (or campus admin for clubs on their campus) assigns plans. No payment gateway. */
export const setEntitlement = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const subjectType = str(req.data?.subjectType, "subjectType") as "club" | "campus" | "brand" | "user";
    const subjectId = str(req.data?.subjectId, "subjectId");
    const key = str(req.data?.key, "key") as EntitlementKey;
    const status = (str(req.data?.status, "status", { optional: true }) || "active") as "active" | "inactive" | "past_due";
    const plan = str(req.data?.plan, "plan", { optional: true, max: 40 });
    const billingStatus = str(req.data?.billingStatus, "billingStatus", { optional: true, max: 40 }) || "manual";
    const validUntil = toDate(req.data?.validUntil);
    const reason = str(req.data?.reason, "reason", { optional: true, max: 300 });
    if (!["organizer_basic", "organizer_premium", "campus_analytics", "brand_dashboard"].includes(key)) fail("invalid_argument", "Unknown entitlement.");
    if (subjectType === "club") {
      const club = await db.collection(COL.clubs).doc(subjectId).get();
      if (!club.exists) fail("not_found");
      await requireMembership(actor, club.get("campusId"), ["campus_admin"]);
    } else {
      await requireSuperAdmin(actor);
    }
    const ref = db.collection(COL.entitlements).doc(`${subjectType}:${subjectId}:${key}`);
    const prev = await ref.get();
    await ref.set({ subjectType, subjectId, key, status, plan: plan || null, billingStatus, validUntil: validUntil ? Timestamp.fromDate(validUntil) : null, grantedBy: actor.uid, updatedAt: serverTs(), ...(prev.exists ? {} : { createdAt: serverTs() }) }, { merge: true });
    writeAudit({ actorUid: actor.uid, action: "entitlement.set", entityType: "entitlement", entityId: ref.id, reason, before: prev.exists ? { status: prev.get("status") } : null, after: { status, plan, billingStatus } });
    return { entitlementId: ref.id };
  }),
);

/** Admin notification composer with audience targeting + cap validation. */
export const sendTargetedNotification = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const title = str(req.data?.title, "title", { max: 80 });
    const body = str(req.data?.body, "body", { max: 240 });
    const route = str(req.data?.route, "route", { optional: true, max: 200 });
    const audience = str(req.data?.audience, "audience") as "all" | "tribe" | "event_rsvps" | "inactive";
    const tribeIds = strArray(req.data?.tribeIds, "tribeIds", { optional: true, max: 10 });
    const eventId = str(req.data?.eventId, "eventId", { optional: true });
    const scheduledFor = toDate(req.data?.scheduledFor) ?? new Date();
    const dryRun = req.data?.dryRun === true;
    const category = "engagement" as const;
    const campaignId = db.collection(COL.notificationJobs).doc().id;
    let uids: string[] = [];
    if (audience === "event_rsvps") {
      if (!eventId) fail("invalid_argument", "eventId required for RSVP targeting.");
      const s = await db.collection(COL.rsvps).where("eventId", "==", eventId).where("status", "in", ["confirmed", "waitlisted"]).select("uid").get();
      uids = s.docs.map((d) => d.get("uid"));
    } else {
      let q = db.collection(COL.memberships).where("campusId", "==", campusId).where("status", "==", "active");
      if (audience === "tribe") { if (tribeIds.length === 0) fail("invalid_argument", "Pick at least one Tribe."); q = q.where("tribeIds", "array-contains-any", tribeIds); }
      const s = await q.select("uid").get();
      uids = s.docs.map((d) => d.get("uid"));
      if (audience === "inactive") {
        const cutoff = Date.now() - 14 * 86400000;
        const active = await db.collection(COL.checkins).where("campusId", "==", campusId).where("at", ">=", Timestamp.fromMillis(cutoff)).select("uid").get();
        const activeSet = new Set(active.docs.map((d) => d.get("uid")));
        uids = uids.filter((u) => !activeSet.has(u));
      }
    }
    if (dryRun) return { campaignId, audienceSize: uids.length, queued: 0 };
    let queued = 0;
    for (const uid of uids) {
      const r = await enqueueNotification({ uid, campusId, category, title, body, route: route || undefined, scheduledFor, dedupeKey: `campaign:${campaignId}:${uid}`, createdBy: actor.uid, data: { campaignId } });
      if (r === "queued") queued++;
    }
    writeAudit({ actorUid: actor.uid, action: "notification.campaign", entityType: "notification_campaign", entityId: campaignId, campusId, after: { title, audience, tribeIds, eventId, audienceSize: uids.length, queued, scheduledFor: scheduledFor.toISOString() } });
    return { campaignId, audienceSize: uids.length, queued };
  }),
);

/** CSV export of campus engagement data (admin). Returns CSV text; institutional export gated by entitlement. */
export const exportCampusData = onCall(
  { ...callableOpts, timeoutSeconds: 300, memory: "1GiB" },
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    const dataset = str(req.data?.dataset, "dataset") as "events" | "attendance" | "redemptions" | "metrics_daily";
    await requireMembership(actor, campusId, ["campus_admin"]);
    const rows: string[][] = [];
    const esc = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`;
    if (dataset === "events") {
      rows.push(["eventId", "title", "club", "status", "startAt", "rsvps", "checkins", "conversionPct", "ratingAvg"]);
      await forEachPage(db.collection(COL.events).where("campusId", "==", campusId).orderBy("startAt"), 500, async (docs) => { for (const d of docs) { const s = d.get("stats") ?? {}; rows.push([d.id, d.get("title"), d.get("clubName"), d.get("status"), new Date(d.get("startAt").toMillis()).toISOString(), s.rsvpCount ?? 0, s.checkinCount ?? 0, s.rsvpCount ? Math.round((s.checkinCount / s.rsvpCount) * 1000) / 10 : 0, s.ratingAvg ?? ""].map(String)); } });
    } else if (dataset === "attendance") {
      rows.push(["eventId", "eventTitle", "uidHash", "method", "at", "tribeIds"]);
      await forEachPage(db.collection(COL.checkins).where("campusId", "==", campusId).orderBy("at"), 500, async (docs) => { for (const d of docs) rows.push([d.get("eventId"), d.get("eventTitle"), d.get("uid").slice(0, 8), d.get("method"), new Date(d.get("at").toMillis()).toISOString(), (d.get("tribeIds") ?? []).join("|")]); });
    } else if (dataset === "redemptions") {
      rows.push(["redemptionId", "reward", "vendorId", "coinCost", "faceValue", "status", "issuedAt", "fulfilledAt", "settlementMonth", "settlementStatus"]);
      await forEachPage(db.collection(COL.redemptions).where("campusId", "==", campusId).orderBy("issuedAt"), 500, async (docs) => { for (const d of docs) rows.push([d.id, d.get("rewardTitle"), d.get("vendorId") ?? "", d.get("coinCost"), d.get("faceValue") ?? "", d.get("status"), new Date(d.get("issuedAt").toMillis()).toISOString(), d.get("fulfilledAt") ? new Date(d.get("fulfilledAt").toMillis()).toISOString() : "", d.get("settlementMonth") ?? "", d.get("settlementStatus")].map(String)); });
    } else if (dataset === "metrics_daily") {
      rows.push(["date", "registered", "activeUsers", "wap", "events", "rsvps", "checkins", "coinsEarned", "coinsRedeemed", "activeOrganizers", "questCompletions"]);
      await forEachPage(db.collection(COL.metricsDaily).where("campusId", "==", campusId).orderBy("date"), 500, async (docs) => { for (const d of docs) rows.push([d.get("date"), d.get("registered"), d.get("activeUsers"), d.get("wap"), d.get("events"), d.get("rsvps"), d.get("checkins"), d.get("coinsEarned"), d.get("coinsRedeemed"), d.get("activeOrganizers"), d.get("questCompletions")].map((v) => String(v ?? 0))); });
    } else fail("invalid_argument", "Unknown dataset.");
    writeAudit({ actorUid: actor.uid, action: "export.campus", entityType: "campus", entityId: campusId, campusId, after: { dataset, rows: rows.length - 1 } });
    return { csv: rows.map((r) => r.map(esc).join(",")).join("\n"), rows: rows.length - 1 };
  }),
);

/** Super admin: manage brand accounts and brand memberships. */
export const upsertBrandAccount = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    await requireSuperAdmin(actor);
    const brandId = str(req.data?.brandId, "brandId", { optional: true });
    const name = str(req.data?.name, "name", { max: 100 });
    const memberUids = strArray(req.data?.memberUids, "memberUids", { optional: true, max: 20 });
    const ref = brandId ? db.collection(COL.brandAccounts).doc(brandId) : db.collection(COL.brandAccounts).doc();
    const b = db.batch();
    b.set(ref, { name, status: str(req.data?.status, "status", { optional: true }) || "active", logoUrl: str(req.data?.logoUrl, "logoUrl", { optional: true, max: 2000 }) || null, updatedAt: serverTs(), createdAt: serverTs() }, { merge: true });
    for (const uid of memberUids) b.set(db.collection(COL.brandMemberships).doc(ids.brandMembership(ref.id, uid)), { brandId: ref.id, uid, status: "active", role: "brand", createdAt: serverTs() }, { merge: true });
    await b.commit();
    writeAudit({ actorUid: actor.uid, action: "brand.upsert", entityType: "brand", entityId: ref.id, after: { name, memberUids } });
    return { brandId: ref.id };
  }),
);

/** Super admin grants/revokes platform super-admin flag (audited). */
export const setSuperAdmin = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    await requireSuperAdmin(actor);
    const uid = str(req.data?.uid, "uid");
    const grant = req.data?.grant === true;
    if (uid === actor.uid && !grant) fail("permission_denied", "You can't remove your own super admin.");
    await db.collection(COL.users).doc(uid).set({ superAdmin: grant }, { merge: true });
    writeAudit({ actorUid: actor.uid, action: grant ? "superadmin.grant" : "superadmin.revoke", entityType: "user", entityId: uid, after: { superAdmin: grant } });
    return { ok: true };
  }),
);
