import { onCall } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { BRAND_MIN_GROUP_SIZE } from "../config/defaults";
import { fail } from "../domain/errors";
import type { CampaignFinancialStatus, QuestStatus, QuestType } from "../domain/types";
import { track } from "../lib/analytics";
import { writeAudit } from "../lib/audit";
import { callableHandler, isSuperAdmin, num, requireAuth, requireMembership, str, strArray } from "../lib/auth";
import { loadCampus, requireFlag } from "../lib/campus";
import { db, inc, serverTs, Timestamp, toDate, tsToMs } from "../lib/firestore";
import { ledgerEntryExists, writeCredit } from "../lib/ledger";
import { enqueueNotification } from "../lib/notifications";
import { callableOpts } from "../lib/options";

const QUEST_TYPES: QuestType[] = ["event_attendance", "qr_activation", "event_count", "checklist", "streak"];
const FIN: CampaignFinancialStatus[] = ["quoted", "approved", "advance_pending", "advance_received", "live", "completed", "final_payment_pending", "paid"];

async function requireBrandMember(req: Parameters<typeof requireAuth>[0], brandId: string) {
  const actor = await requireAuth(req);
  const m = await db.collection(COL.brandMemberships).doc(ids.brandMembership(brandId, actor.uid)).get();
  if (!m.exists || m.get("status") !== "active") {
    if (!(await isSuperAdmin(actor.uid))) fail("permission_denied", "You don't have access to this brand account.");
  }
  return actor;
}

/** Brand user saves a draft (create or update). Only drafts are editable. */
export const saveQuestDraft = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const brandId = str(req.data?.brandId, "brandId");
    const actor = await requireBrandMember(req, brandId);
    const d = req.data ?? {};
    const questId = str(d.questId, "questId", { optional: true });
    const type = str(d.type, "type") as QuestType;
    if (!QUEST_TYPES.includes(type)) fail("invalid_argument", "Unknown quest type.");
    const startAt = toDate(d.startAt);
    const endAt = toDate(d.endAt);
    if (!startAt || !endAt || endAt <= startAt) fail("invalid_argument", "Quest needs a valid start and end.");
    const criteria = (d.criteria ?? {}) as Record<string, unknown>;
    const doc = {
      brandId,
      title: str(d.title, "title", { max: 100 }),
      description: str(d.description, "description", { max: 2000 }),
      creativeUrl: str(d.creativeUrl, "creativeUrl", { optional: true, max: 2000 }) || null,
      campusIds: strArray(d.campusIds, "campusIds", { max: 50 }),
      tribeIds: strArray(d.tribeIds, "tribeIds", { optional: true, max: 20 }),
      startAt: Timestamp.fromDate(startAt!),
      endAt: Timestamp.fromDate(endAt!),
      type,
      criteria: {
        eventIds: strArray(criteria.eventIds, "criteria.eventIds", { optional: true, max: 50 }),
        count: num(criteria.count, "criteria.count", { optional: true, min: 1, max: 100, int: true }),
        checklist: Array.isArray(criteria.checklist) ? (criteria.checklist as unknown[]).slice(0, 20).map((c) => String(c).slice(0, 200)) : [],
        streakWeeks: num(criteria.streakWeeks, "criteria.streakWeeks", { optional: true, min: 1, max: 12, int: true }),
        tagFilter: strArray(criteria.tagFilter, "criteria.tagFilter", { optional: true, max: 10 }),
      },
      rewardCoins: num(d.rewardCoins, "rewardCoins", { min: 0, max: 1000, int: true }),
      participantLimit: num(d.participantLimit, "participantLimit", { optional: true, min: 0, max: 100000, int: true }),
      campaignValue: num(d.campaignValue, "campaignValue", { optional: true, min: 0 }),
      terms: str(d.terms, "terms", { optional: true, max: 3000 }),
      sponsorDisclosure: str(d.sponsorDisclosure, "sponsorDisclosure", { optional: true, max: 300 }) || "Sponsored quest",
      updatedAt: serverTs(),
      updatedBy: actor.uid,
    };
    if (doc.campusIds.length === 0) fail("invalid_argument", "Select at least one campus.");
    const ref = questId ? db.collection(COL.quests).doc(questId) : db.collection(COL.quests).doc();
    await db.runTransaction(async (tx) => {
      const prev = await tx.get(ref);
      if (prev.exists) {
        if (prev.get("brandId") !== brandId) fail("permission_denied");
        if (prev.get("status") !== "draft") fail("invalid_argument", "Only drafts can be edited. Pause the quest to make changes.");
        tx.set(ref, doc, { merge: true });
      } else {
        tx.set(ref, { ...doc, status: "draft" as QuestStatus, financialStatus: "quoted" as CampaignFinancialStatus, stats: { views: 0, joins: 0, completions: 0, coinsDistributed: 0, campusBreakdown: {}, tribeBreakdown: {} }, createdAt: serverTs(), createdBy: actor.uid });
      }
    });
    return { questId: ref.id };
  }),
);

export const submitBrandQuest = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const questId = str(req.data?.questId, "questId");
    const ref = db.collection(COL.quests).doc(questId);
    const snap = await ref.get();
    if (!snap.exists) fail("not_found");
    await requireBrandMember(req, snap.get("brandId"));
    if (snap.get("status") !== "draft") fail("invalid_argument", "Only drafts can be submitted.");
    await ref.update({ status: "submitted", submittedAt: serverTs() });
    return { ok: true };
  }),
);

/** CampusBuzz admin (super admin or admin of every participating campus) approves/rejects. */
export const approveBrandQuest = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const questId = str(req.data?.questId, "questId");
    const approve = req.data?.approve !== false;
    const reason = str(req.data?.reason, "reason", { optional: true, max: 500 });
    const ref = db.collection(COL.quests).doc(questId);
    const snap = await ref.get();
    if (!snap.exists) fail("not_found");
    if (!(await isSuperAdmin(actor.uid))) {
      for (const c of snap.get("campusIds") as string[]) await requireMembership(actor, c, ["campus_admin"]);
    }
    if (snap.get("status") !== "submitted") fail("invalid_argument", "Only submitted quests can be reviewed.");
    for (const c of snap.get("campusIds") as string[]) await requireFlag(c, "brand_quests_enabled");
    const nowMs = Date.now();
    const status: QuestStatus = approve ? ((tsToMs(snap.get("startAt")) ?? nowMs) <= nowMs ? "live" : "approved") : "draft";
    await ref.update({ status, approvedBy: approve ? actor.uid : null, approvedAt: approve ? serverTs() : null, rejectionReason: approve ? null : reason, financialStatus: approve ? "approved" : snap.get("financialStatus") });
    writeAudit({ actorUid: actor.uid, action: approve ? "quest.approve" : "quest.reject", entityType: "quest", entityId: questId, reason, before: { status: "submitted" }, after: { status } });
    return { status };
  }),
);

/** Brand or admin pauses/resumes/cancels/completes; admin can set financial status. */
export const updateQuestStatus = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const questId = str(req.data?.questId, "questId");
    const status = str(req.data?.status, "status", { optional: true }) as QuestStatus | "";
    const financialStatus = str(req.data?.financialStatus, "financialStatus", { optional: true }) as CampaignFinancialStatus | "";
    const ref = db.collection(COL.quests).doc(questId);
    const snap = await ref.get();
    if (!snap.exists) fail("not_found");
    const superAdmin = await isSuperAdmin(actor.uid);
    const brandMember = (await db.collection(COL.brandMemberships).doc(ids.brandMembership(snap.get("brandId"), actor.uid)).get()).exists;
    if (!superAdmin && !brandMember) fail("permission_denied");
    const update: Record<string, unknown> = { updatedAt: serverTs() };
    if (status) {
      const allowedBrand: QuestStatus[] = ["paused", "live", "cancelled", "completed"];
      if (!superAdmin && !allowedBrand.includes(status)) fail("permission_denied", "Brands can pause, resume, complete or cancel.");
      const current = snap.get("status") as QuestStatus;
      if (status === "live" && !["paused", "approved"].includes(current)) fail("invalid_argument", "Only paused or approved quests can go live.");
      if (status === "paused" && current !== "live") fail("invalid_argument", "Only live quests can be paused.");
      update.status = status;
    }
    if (financialStatus) {
      if (!superAdmin) fail("permission_denied", "Financial status is managed by CampusBuzz.");
      if (!FIN.includes(financialStatus)) fail("invalid_argument");
      update.financialStatus = financialStatus;
    }
    await ref.update(update);
    writeAudit({ actorUid: actor.uid, action: "quest.status", entityType: "quest", entityId: questId, before: { status: snap.get("status"), financialStatus: snap.get("financialStatus") }, after: update });
    return { ok: true };
  }),
);

/** Student joins a live quest they are eligible for. */
export const joinQuest = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const questId = str(req.data?.questId, "questId");
    const campusId = actor.user?.activeCampusId as string;
    await requireMembership(actor, campusId);
    await requireFlag(campusId, "brand_quests_enabled");
    const ref = db.collection(COL.quests).doc(questId);
    const compRef = db.collection(COL.questCompletions).doc(ids.questCompletion(questId, actor.uid));
    const tribeIds: string[] = actor.user?.tribeIds ?? [];
    await db.runTransaction(async (tx) => {
      const [q, existing] = await Promise.all([tx.get(ref), tx.get(compRef)]);
      if (!q.exists) fail("not_found");
      if (existing.exists) return;
      if (q.get("status") !== "live") fail("quest_not_live", "This quest isn't live right now.");
      if (Date.now() > (tsToMs(q.get("endAt")) ?? 0)) fail("quest_not_live", "This quest has ended.");
      if (!(q.get("campusIds") as string[]).includes(campusId)) fail("quest_not_eligible", "This quest isn't running on your campus.");
      const qt: string[] = q.get("tribeIds") ?? [];
      if (qt.length > 0 && !qt.some((t) => tribeIds.includes(t))) fail("quest_not_eligible", "This quest is for other Tribes.");
      const limit = Number(q.get("participantLimit") ?? 0);
      if (limit > 0 && Number(q.get("stats.joins") ?? 0) >= limit) fail("quest_full", "This quest is full.");
      tx.set(compRef, { questId, uid: actor.uid, campusId, tribeIds, status: "joined", progress: { eventIds: [], checklist: [], count: 0 }, joinedAt: serverTs(), completedAt: null, coinsAwarded: 0, brandId: q.get("brandId"), questTitle: q.get("title") });
      tx.update(ref, { "stats.joins": inc(1), [`stats.campusBreakdown.${campusId}.joins`]: inc(1) });
    });
    await track("quest_joined", { uid: actor.uid, campusId, questId, tribeIds });
    return { ok: true };
  }),
);

/** Student ticks checklist items (checklist/survey quests). Completion awards once. */
export const submitQuestChecklist = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const questId = str(req.data?.questId, "questId");
    const items = strArray(req.data?.items, "items", { max: 20 });
    const campusId = actor.user?.activeCampusId as string;
    await requireMembership(actor, campusId);
    const q = await db.collection(COL.quests).doc(questId).get();
    if (!q.exists || q.get("type") !== "checklist") fail("invalid_argument", "This quest doesn't use a checklist.");
    const required: string[] = q.get("criteria.checklist") ?? [];
    const done = items.filter((i) => required.includes(i));
    await db.collection(COL.questCompletions).doc(ids.questCompletion(questId, actor.uid)).set({ "progress.checklist": done, updatedAt: serverTs() }, { merge: true });
    if (done.length >= required.length && required.length > 0) await completeQuestInternal(questId, actor.uid);
    return { done: done.length, required: required.length };
  }),
);

/** Called after every verified check-in to progress attendance-based quests. */
export async function evaluateQuestsForCheckin(p: { uid: string; campusId: string; eventId: string; tribeIds: string[] }): Promise<void> {
  const joined = await db.collection(COL.questCompletions).where("uid", "==", p.uid).where("status", "==", "joined").get();
  if (joined.empty) return;
  const ev = await db.collection(COL.events).doc(p.eventId).get();
  const evTags: string[] = [...(ev.get("tags") ?? []), ...(ev.get("tribeIds") ?? [])];
  for (const c of joined.docs) {
    const q = await db.collection(COL.quests).doc(c.get("questId")).get();
    if (!q.exists || q.get("status") !== "live") continue;
    const type = q.get("type") as QuestType;
    const criteria = q.get("criteria") ?? {};
    const tagFilter: string[] = criteria.tagFilter ?? [];
    if (tagFilter.length > 0 && !tagFilter.some((t) => evTags.includes(t))) continue;
    let complete = false;
    if (type === "event_attendance") {
      const targets: string[] = criteria.eventIds ?? [];
      if (targets.length === 0 || targets.includes(p.eventId)) complete = true;
    } else if (type === "event_count") {
      const prev: string[] = c.get("progress.eventIds") ?? [];
      if (!prev.includes(p.eventId)) {
        const next = [...prev, p.eventId];
        await c.ref.update({ "progress.eventIds": next, "progress.count": next.length, updatedAt: serverTs() });
        complete = next.length >= Number(criteria.count ?? 1);
      }
    } else if (type === "streak") {
      const stats = await db.collection(COL.participationStats).doc(p.uid).get();
      complete = Number(stats.get("streak") ?? 0) >= Number(criteria.streakWeeks ?? 3);
    } else if (type === "qr_activation") {
      const targets: string[] = criteria.eventIds ?? [];
      complete = targets.includes(p.eventId);
    }
    if (complete) await completeQuestInternal(q.id, p.uid);
  }
}

export async function completeQuestInternal(questId: string, uid: string): Promise<number> {
  const compRef = db.collection(COL.questCompletions).doc(ids.questCompletion(questId, uid));
  const qRef = db.collection(COL.quests).doc(questId);
  const key = ids.ledger.quest(questId, uid);
  const out = await db.runTransaction(async (tx) => {
    const [c, q, exists] = await Promise.all([tx.get(compRef), tx.get(qRef), ledgerEntryExists(tx, key)]);
    if (!c.exists || c.get("status") === "completed") return { coins: 0, campusId: c.get("campusId"), title: q.get("title") };
    const campusId = c.get("campusId") as string;
    const campus = await loadCampus(campusId, tx);
    const coins = writeCredit(tx, { key, uid, campusId, type: "credit", reason: "quest", amount: Number(q.get("rewardCoins") ?? 0), refId: questId, economy: campus.economy, alreadyExists: exists, meta: { brandId: q.get("brandId") } });
    tx.update(compRef, { status: "completed", completedAt: serverTs(), coinsAwarded: coins });
    const tribeInc: Record<string, unknown> = {};
    for (const t of (c.get("tribeIds") as string[]) ?? []) tribeInc[`stats.tribeBreakdown.${t}`] = inc(1);
    tx.update(qRef, { "stats.completions": inc(1), "stats.coinsDistributed": inc(coins), [`stats.campusBreakdown.${campusId}.completions`]: inc(1), ...tribeInc });
    return { coins, campusId, title: q.get("title") as string };
  });
  if (out.coins >= 0 && out.campusId) {
    await track("quest_completed", { uid, campusId: out.campusId, questId, coins: out.coins });
    await enqueueNotification({ uid, campusId: out.campusId, category: "transactional", title: "Quest complete", body: `${out.title}${out.coins > 0 ? ` · +${out.coins} BuzzCoins` : ""}`, route: `/quests/${questId}`, dedupeKey: `quest:${questId}:${uid}:complete` });
  }
  return out.coins;
}

/** Aggregate brand analytics. Small groups are suppressed (min group size). */
export const getBrandQuestAnalytics = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const questId = str(req.data?.questId, "questId");
    const q = await db.collection(COL.quests).doc(questId).get();
    if (!q.exists) fail("not_found");
    await requireBrandMember(req, q.get("brandId"));
    for (const c of q.get("campusIds") as string[]) await requireFlag(c, "brand_dashboard_enabled");
    const stats = q.get("stats") ?? {};
    const campusIds: string[] = q.get("campusIds") ?? [];
    const tribeIds: string[] = q.get("tribeIds") ?? [];
    // Eligible audience = active members of participating campuses (filtered by Tribe if set).
    let eligible = 0;
    for (const c of campusIds) {
      let qq = db.collection(COL.memberships).where("campusId", "==", c).where("status", "==", "active");
      if (tribeIds.length > 0) qq = qq.where("tribeIds", "array-contains-any", tribeIds.slice(0, 10));
      eligible += (await qq.count().get()).data().count;
    }
    const completions = await db.collection(COL.questCompletions).where("questId", "==", questId).where("status", "==", "completed").select("uid", "completedAt").get();
    const completerUids = completions.docs.map((d) => d.get("uid") as string);
    // Repeat participation = completers who completed ≥1 other quest from this brand.
    let repeat = 0;
    if (completerUids.length > 0) {
      const others = await db.collection(COL.questCompletions).where("brandId", "==", q.get("brandId")).where("status", "==", "completed").select("uid", "questId").get();
      const byUid = new Map<string, Set<string>>();
      others.docs.forEach((d) => byUid.set(d.get("uid"), (byUid.get(d.get("uid")) ?? new Set()).add(d.get("questId"))));
      repeat = completerUids.filter((u) => (byUid.get(u)?.size ?? 0) >= 2).length;
    }
    const suppress = (obj: Record<string, number>) => Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, v < BRAND_MIN_GROUP_SIZE ? null : v]));
    const tribeBreakdown = suppress(stats.tribeBreakdown ?? {});
    const campusBreakdown = Object.fromEntries(Object.entries(stats.campusBreakdown ?? {}).map(([k, v]) => [k, suppress(v as Record<string, number>)]));
    const timeline: Record<string, number> = {};
    completions.docs.forEach((d) => {
      const ms = tsToMs(d.get("completedAt"));
      if (ms) {
        const day = new Date(ms).toISOString().slice(0, 10);
        timeline[day] = (timeline[day] ?? 0) + 1;
      }
    });
    const value = Number(q.get("campaignValue") ?? 0);
    const completionsN = Number(stats.completions ?? 0);
    return {
      eligibleAudience: eligible,
      views: stats.views ?? 0,
      joins: stats.joins ?? 0,
      completions: completionsN,
      completionRate: stats.joins ? Math.round((completionsN / stats.joins) * 1000) / 10 : 0,
      repeatParticipation: repeat,
      coinsDistributed: stats.coinsDistributed ?? 0,
      costPerVerifiedAction: value > 0 && completionsN > 0 ? Math.round((value / completionsN) * 100) / 100 : null,
      campusBreakdown,
      tribeBreakdown,
      timeline,
      minGroupSize: BRAND_MIN_GROUP_SIZE,
      financialStatus: q.get("financialStatus"),
      status: q.get("status"),
    };
  }),
);
