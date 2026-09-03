import { onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { COL, ids } from "../config/collections";
import { DEFAULT_BUZZ_SCORE_WEIGHTS } from "../config/defaults";
import { campusBuzzScore } from "../domain/buzzScore";
import { economyHealth } from "../domain/economy";
import { fail } from "../domain/errors";
import { nps as computeNps, organizerSupplyHealth, percent, redemptionRates, repeatAttendeeRate, rsvpToAttendance, week6Retention, wouldMissPercent } from "../domain/metrics";
import { buildScorecard } from "../domain/scorecard";
import { addDays, isoWeekKey, localDateKey, previousWeekKey, weeksBetween } from "../domain/time";
import { callableHandler, canManageEvent, requireAuth, requireMembership, str } from "../lib/auth";
import { CampusDoc, loadCampus, normalizeCampus } from "../lib/campus";
import { db, forEachPage, serverTs, Timestamp, tsToMs } from "../lib/firestore";
import { callableOpts, scheduleOpts } from "../lib/options";

/* ------------------------------------------------------------------ */
/* Daily aggregation                                                   */
/* ------------------------------------------------------------------ */

async function countWhere(q: FirebaseFirestore.Query): Promise<number> {
  return (await q.count().get()).data().count;
}

/** Aggregates one campus-day into metrics_daily/{campusId_date}. Idempotent (overwrites). */
export async function aggregateCampusDay(campus: CampusDoc, dayStartUtc: Date): Promise<void> {
  const tz = campus.timezone;
  const dateKey = localDateKey(dayStartUtc, tz);
  // Compute local day bounds by scanning ±1 day and filtering by local date key — cheap and DST-safe.
  const from = Timestamp.fromDate(addDays(dayStartUtc, -1));
  const to = Timestamp.fromDate(addDays(dayStartUtc, 2));
  const inDay = (d: FirebaseFirestore.QueryDocumentSnapshot, field: string) => {
    const ms = tsToMs(d.get(field));
    return ms !== null && localDateKey(new Date(ms), tz) === dateKey;
  };
  const [checkins, rsvps, ledger, events, joins, memberships] = await Promise.all([
    db.collection(COL.checkins).where("campusId", "==", campus.id).where("at", ">=", from).where("at", "<", to).get(),
    db.collection(COL.rsvps).where("campusId", "==", campus.id).where("createdAt", ">=", from).where("createdAt", "<", to).get(),
    db.collection(COL.coinLedger).where("campusId", "==", campus.id).where("createdAt", ">=", from).where("createdAt", "<", to).get(),
    db.collection(COL.events).where("campusId", "==", campus.id).where("publishedAt", ">=", from).where("publishedAt", "<", to).get(),
    db.collection(COL.questCompletions).where("campusId", "==", campus.id).where("completedAt", ">=", from).where("completedAt", "<", to).get(),
    countWhere(db.collection(COL.memberships).where("campusId", "==", campus.id).where("status", "==", "active")),
  ]);
  const dayCheckins = checkins.docs.filter((d) => inDay(d, "at"));
  const dayRsvps = rsvps.docs.filter((d) => inDay(d, "createdAt"));
  const dayLedger = ledger.docs.filter((d) => inDay(d, "createdAt"));
  const dayEvents = events.docs.filter((d) => inDay(d, "publishedAt"));
  const activeUids = new Set<string>([...dayCheckins.map((d) => d.get("uid")), ...dayRsvps.map((d) => d.get("uid"))]);
  const weekKey = isoWeekKey(dayStartUtc, tz);
  const weekCheckins = await db.collection(COL.checkins).where("campusId", "==", campus.id).where("weekKey", "==", weekKey).select("uid").get();
  const wap = new Set(weekCheckins.docs.map((d) => d.get("uid"))).size;
  const doc = {
    campusId: campus.id,
    date: dateKey,
    weekKey,
    registered: memberships,
    activeUsers: activeUids.size,
    wap,
    wapPercent: percent(wap, memberships),
    events: dayEvents.length,
    rsvps: dayRsvps.length,
    checkins: dayCheckins.length,
    manualCheckins: dayCheckins.filter((d) => d.get("method") === "manual").length,
    coinsEarned: dayLedger.filter((d) => d.get("type") === "credit").reduce((s, d) => s + Number(d.get("amount")), 0),
    coinsRedeemed: dayLedger.filter((d) => d.get("reason") === "redemption").reduce((s, d) => s - Number(d.get("amount")), 0),
    coinsExpired: dayLedger.filter((d) => d.get("type") === "expiry").reduce((s, d) => s - Number(d.get("amount")), 0),
    activeOrganizers: new Set(dayEvents.map((d) => d.get("clubId"))).size,
    questCompletions: joins.docs.filter((d) => inDay(d, "completedAt")).length,
    updatedAt: serverTs(),
  };
  await db.collection(COL.metricsDaily).doc(ids.metricsDaily(campus.id, dateKey)).set(doc);
}

export async function aggregateAllCampuses(day: Date): Promise<number> {
  const campuses = await db.collection(COL.campuses).where("status", "==", "active").get();
  for (const c of campuses.docs) await aggregateCampusDay(normalizeCampus(c.id, c.data()), day);
  return campuses.size;
}

/** Runs nightly (02:15 IST) for yesterday and today, so late check-ins are captured. */
export const aggregateDailyCampusMetrics = onSchedule({ ...scheduleOpts, schedule: "15 2 * * *", timeZone: "Asia/Kolkata" }, async () => {
  await aggregateAllCampuses(addDays(new Date(), -1));
  await aggregateAllCampuses(new Date());
});

/** Admin can trigger aggregation on demand (e.g. right after seeding or before a demo). */
export const runMetricsAggregation = onCall(
  { ...callableOpts, timeoutSeconds: 300 },
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const campus = await loadCampus(campusId);
    const days = Math.min(60, Math.max(1, Number(req.data?.days ?? 14)));
    for (let i = days - 1; i >= 0; i--) await aggregateCampusDay(campus, addDays(new Date(), -i));
    await computeLeaderboard(campus, new Date());
    return { days };
  }),
);

/* ------------------------------------------------------------------ */
/* Tribe leaderboard (weekly, verified check-ins only)                 */
/* ------------------------------------------------------------------ */

export async function computeLeaderboard(campus: CampusDoc, at: Date): Promise<void> {
  const weekKey = isoWeekKey(at, campus.timezone);
  const prevKey = previousWeekKey(weekKey);
  const tally = async (wk: string) => {
    const counts: Record<string, number> = {};
    await forEachPage(db.collection(COL.checkins).where("campusId", "==", campus.id).where("weekKey", "==", wk), 500, async (docs) => {
      for (const d of docs) for (const t of (d.get("tribeIds") as string[]) ?? []) counts[t] = (counts[t] ?? 0) + 1;
    });
    return counts;
  };
  const [cur, prev] = await Promise.all([tally(weekKey), tally(prevKey)]);
  const rank = (c: Record<string, number>) => Object.entries(c).sort((a, b) => b[1] - a[1]).map(([tribeId, count], i) => ({ tribeId, count, rank: i + 1 }));
  const prevRanks = new Map(rank(prev).map((r) => [r.tribeId, r.rank]));
  const tribes = await db.collection(COL.tribes).where("campusId", "==", campus.id).get();
  const allTribeIds = tribes.docs.map((t) => t.id);
  for (const t of allTribeIds) cur[t] = cur[t] ?? 0;
  const rows = rank(cur).map((r) => ({ ...r, previousRank: prevRanks.get(r.tribeId) ?? null, movement: prevRanks.has(r.tribeId) ? prevRanks.get(r.tribeId)! - r.rank : null, name: tribes.docs.find((d) => d.id === r.tribeId)?.get("name") ?? r.tribeId }));
  await db.collection(COL.tribeLeaderboards).doc(ids.leaderboard(campus.id, weekKey)).set({ campusId: campus.id, weekKey, rows, updatedAt: serverTs() });
  await db.collection(COL.tribeLeaderboards).doc(`${campus.id}_current`).set({ campusId: campus.id, weekKey, rows, updatedAt: serverTs() });
}

export const refreshTribeLeaderboards = onSchedule({ ...scheduleOpts, schedule: "every 30 minutes" }, async () => {
  const campuses = await db.collection(COL.campuses).where("status", "==", "active").get();
  for (const c of campuses.docs) await computeLeaderboard(normalizeCampus(c.id, c.data()), new Date());
});

/* ------------------------------------------------------------------ */
/* Campus dashboard + pilot scorecard                                  */
/* ------------------------------------------------------------------ */

async function campusWeekStats(campus: CampusDoc, at: Date) {
  const tz = campus.timezone;
  const weekKey = isoWeekKey(at, tz);
  const [registered, weekCheckins, weekRsvps, weekEvents] = await Promise.all([
    countWhere(db.collection(COL.memberships).where("campusId", "==", campus.id).where("status", "==", "active")),
    db.collection(COL.checkins).where("campusId", "==", campus.id).where("weekKey", "==", weekKey).select("uid", "eventId").get(),
    countWhere(db.collection(COL.rsvps).where("campusId", "==", campus.id).where("createdAt", ">=", Timestamp.fromDate(addDays(at, -7)))),
    db.collection(COL.events).where("campusId", "==", campus.id).where("publishedAt", ">=", Timestamp.fromDate(addDays(at, -7))).select("clubId").get(),
  ]);
  const wap = new Set(weekCheckins.docs.map((d) => d.get("uid"))).size;
  return { weekKey, registered, wap, wapPercent: percent(wap, registered), weekCheckins: weekCheckins.size, weekRsvps, organizersPostingWeekly: new Set(weekEvents.docs.map((d) => d.get("clubId"))).size, eventsPostedWeekly: weekEvents.size };
}

async function conversionLast30(campusId: string, at: Date) {
  const since = Timestamp.fromDate(addDays(at, -30));
  const events = await db.collection(COL.events).where("campusId", "==", campusId).where("startAt", ">=", since).where("startAt", "<=", Timestamp.fromDate(at)).where("status", "in", ["published", "completed"]).select("stats").get();
  let rsvps = 0, checkins = 0;
  events.docs.forEach((d) => { rsvps += Number(d.get("stats.rsvpCount") ?? 0); checkins += Number(d.get("stats.checkinCount") ?? 0); });
  return { rsvps, checkins, pct: rsvpToAttendance(checkins, rsvps), events: events.size };
}

async function latestSurvey(campusId: string) {
  const surveys = await db.collection(COL.surveys).where("campusId", "==", campusId).orderBy("createdAt", "desc").limit(1).get();
  if (surveys.empty) return { nps: null as number | null, wouldMiss: null as number | null, responses: 0, surveyId: null as string | null };
  const s = surveys.docs[0];
  const responses = await db.collection(COL.surveyResponses).where("surveyId", "==", s.id).select("answers").get();
  const scores = responses.docs.map((d) => Number(d.get("answers.nps"))).filter((n) => Number.isFinite(n));
  const wm = responses.docs.map((d) => d.get("answers.wouldMiss")).filter(Boolean);
  const n = computeNps(scores);
  return { nps: scores.length ? n.nps : null, wouldMiss: wm.length ? wouldMissPercent(wm) : null, responses: responses.size, surveyId: s.id, npsDetail: n };
}

/** Week-6 retention of the campus's first-week cohort (both definitions). */
async function retention(campus: CampusDoc, at: Date) {
  const tz = campus.timezone;
  const first = await db.collection(COL.memberships).where("campusId", "==", campus.id).orderBy("joinedAt").limit(1).get();
  if (first.empty) return { product: null, participation: null, cohortSize: 0, cohortWeek: null as string | null, ready: false };
  const cohortWeek = isoWeekKey(new Date(tsToMs(first.docs[0].get("joinedAt"))!), tz);
  const nowWeek = isoWeekKey(at, tz);
  if (weeksBetween(cohortWeek, nowWeek) < 5) return { product: null, participation: null, cohortSize: 0, cohortWeek, ready: false };
  const cohort = await db.collection(COL.memberships).where("campusId", "==", campus.id).select("uid", "joinedAt").get();
  const cohortUids = cohort.docs.filter((d) => isoWeekKey(new Date(tsToMs(d.get("joinedAt"))!), tz) === cohortWeek).map((d) => d.get("uid") as string);
  // Week 6 = cohortWeek + 5
  const w6 = (() => { let k = cohortWeek; for (let i = 0; i < 5; i++) k = nextWeekKey(k); return k; })();
  const [w6Checkins, w6Rsvps] = await Promise.all([
    db.collection(COL.checkins).where("campusId", "==", campus.id).where("weekKey", "==", w6).select("uid").get(),
    db.collection(COL.rsvps).where("campusId", "==", campus.id).where("createdAt", ">=", Timestamp.fromDate(mondayOf(w6))).where("createdAt", "<", Timestamp.fromDate(addDays(mondayOf(w6), 7))).select("uid").get(),
  ]);
  const checked = w6Checkins.docs.map((d) => d.get("uid") as string);
  const active = [...checked, ...w6Rsvps.docs.map((d) => d.get("uid") as string)];
  const r = week6Retention({ cohortUids, activeWeek6Uids: active, checkedInWeek6Uids: checked });
  return { ...r, cohortWeek, ready: true };
}

function nextWeekKey(k: string): string { return isoWeekKey(addDays(mondayOf(k), 7), "UTC"); }
function mondayOf(weekKey: string): Date {
  const m = /^(\d{4})-W(\d{2})$/.exec(weekKey)!;
  const year = Number(m[1]), week = Number(m[2]);
  const jan4 = new Date(Date.UTC(year, 0, 4));
  const jan4Day = jan4.getUTCDay() || 7;
  return new Date(jan4.getTime() - (jan4Day - 1) * 86400000 + (week - 1) * 7 * 86400000);
}

export const getCampusDashboard = onCall(
  { ...callableOpts, timeoutSeconds: 120 },
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const campus = await loadCampus(campusId);
    const at = new Date();
    const tz = campus.timezone;
    const todayKey = localDateKey(at, tz), tomorrowKey = localDateKey(addDays(at, 1), tz);
    const [week, conv, survey, ret, upcoming, rewardsActive, redemptionsMonth, ledgerMonth, pendingReview, pendingRoles, daily] = await Promise.all([
      campusWeekStats(campus, at),
      conversionLast30(campusId, at),
      latestSurvey(campusId),
      retention(campus, at),
      db.collection(COL.events).where("campusId", "==", campusId).where("status", "==", "published").where("startAt", ">=", Timestamp.fromDate(at)).where("startAt", "<=", Timestamp.fromDate(addDays(at, 7))).select("startAt", "clubId").get(),
      db.collection(COL.rewards).where("campusId", "==", campusId).where("status", "==", "active").select("coinCost", "inventory", "faceValue").get(),
      db.collection(COL.redemptions).where("campusId", "==", campusId).where("issuedAt", ">=", Timestamp.fromDate(addDays(at, -30))).select("uid", "coinCost").get(),
      db.collection(COL.coinLedger).where("campusId", "==", campusId).where("createdAt", ">=", Timestamp.fromDate(addDays(at, -30))).select("uid", "amount", "type", "reason", "createdAt").get(),
      countWhere(db.collection(COL.events).where("campusId", "==", campusId).where("reviewStatus", "in", ["pending_review", "flagged"])),
      countWhere(db.collection(COL.memberships).where("campusId", "==", campusId).where("requestedRoles", "!=", [])),
      db.collection(COL.metricsDaily).where("campusId", "==", campusId).orderBy("date", "desc").limit(42).get(),
    ]);
    const eventsTodayTomorrow = upcoming.docs.filter((d) => { const k = localDateKey(new Date(tsToMs(d.get("startAt"))!), tz); return k === todayKey || k === tomorrowKey; }).length;
    const supply = organizerSupplyHealth({ organizersPostingThisWeek: week.organizersPostingWeekly, eventsPostedThisWeek: week.eventsPostedWeekly, eventsNext7Days: upcoming.size, eventsTodayTomorrow, weeklyEventsTarget: campus.pilot.targets.weeklyEventsTarget, minEventsTodayTomorrow: campus.pilot.targets.minEventsTodayTomorrow });
    const earnedDocs = ledgerMonth.docs.filter((d) => d.get("type") === "credit");
    const coinsEarnedMonth = earnedDocs.reduce((s, d) => s + Number(d.get("amount")), 0);
    const coinsRedeemedMonth = ledgerMonth.docs.filter((d) => d.get("reason") === "redemption").reduce((s, d) => s - Number(d.get("amount")), 0);
    const weekAgo = addDays(at, -7).getTime();
    const weekLedger = earnedDocs.filter((d) => (tsToMs(d.get("createdAt")) ?? 0) >= weekAgo);
    const redeemableCoins = rewardsActive.docs.reduce((s, d) => s + Number(d.get("coinCost") ?? 0) * (d.get("inventory") === null ? 50 : Number(d.get("inventory") ?? 0)), 0);
    const redeemableValue = rewardsActive.docs.reduce((s, d) => s + Number(d.get("faceValue") ?? 0) * (d.get("inventory") === null ? 50 : Number(d.get("inventory") ?? 0)), 0);
    const eh = economyHealth({ coinsEarnedMonth, coinsRedeemedMonth, usersEarned: new Set(earnedDocs.map((d) => d.get("uid"))).size, usersRedeemed: new Set(redemptionsMonth.docs.map((d) => d.get("uid"))).size, activeUsersWeek: new Set(weekLedger.map((d) => d.get("uid"))).size, coinsEarnedWeek: weekLedger.reduce((s, d) => s + Number(d.get("amount")), 0), redeemableInventoryValueCoins: redeemableCoins }, campus.pilot.economyHealth);
    const rr = redemptionRates({ coinsRedeemed: coinsRedeemedMonth, coinsEarned: coinsEarnedMonth, usersRedeemed: new Set(redemptionsMonth.docs.map((d) => d.get("uid"))).size, usersEarned: new Set(earnedDocs.map((d) => d.get("uid"))).size });
    const balances = await db.collection(COL.coinBalances).where("campusId", "==", campusId).select("balance").get();
    const outstanding = balances.docs.reduce((s, d) => s + Number(d.get("balance") ?? 0), 0);
    const scorecard = buildScorecard({ registeredStudents: week.registered, wapPercent: week.wapPercent, week6Retention: ret.participation, organizersPostingWeekly: week.organizersPostingWeekly, rsvpToAttendance: conv.events > 0 ? conv.pct : null, nps: survey.nps, wouldMiss: survey.wouldMiss }, campus.pilot.bands);
    const buzz = campus.featureFlags.campus_buzz_score_enabled ? campusBuzzScore({ wapPercent: week.wapPercent, rsvpToAttendance: conv.pct, eventsThisWeek: week.eventsPostedWeekly, weeklyEventsTarget: campus.pilot.targets.weeklyEventsTarget, retentionPercent: ret.participation ?? 0 }, DEFAULT_BUZZ_SCORE_WEIGHTS) : null;
    const warnings: Array<{ code: string; message: string }> = [];
    for (const f of supply.flags) warnings.push({ code: f, message: { no_upcoming_events: "No upcoming events in the next 7 days.", empty_feed_risk: `Fewer than ${campus.pilot.targets.minEventsTodayTomorrow} events today/tomorrow.`, below_weekly_event_target: `Only ${week.eventsPostedWeekly} events posted this week (target ${campus.pilot.targets.weeklyEventsTarget}).` }[f] ?? f });
    if (week.registered > 0 && week.wapPercent < campus.pilot.bands.wapPercent.red) warnings.push({ code: "low_wap", message: `WAP is ${week.wapPercent}% — below the ${campus.pilot.bands.wapPercent.red}% pilot floor.` });
    for (const w of eh.warnings) warnings.push({ code: w, message: { high_weekly_earn: `Average weekly earn is ${Math.round(eh.avgWeeklyEarnPerUser)} coins/user (warning > ${campus.pilot.economyHealth.weeklyEarnWarning}).`, low_redemption_rate: `Redemption rate is ${Math.round(rr.byCoins)}% (warning < ${campus.pilot.economyHealth.redemptionWarning}%).`, earned_exceeds_redeemable: `Coins earned this month exceed ${campus.pilot.economyHealth.maxEarnedToRedeemableRatio}× redeemable inventory.`, no_redeemable_inventory: "Coins are being earned but nothing is redeemable." }[w] ?? w });
    const qr = await db.collection(COL.eventQrSessions).where("campusId", "==", campusId).select("scanFailures", "scanSuccesses").get();
    const fails = qr.docs.reduce((s, d) => s + Number(d.get("scanFailures") ?? 0), 0), succ = qr.docs.reduce((s, d) => s + Number(d.get("scanSuccesses") ?? 0), 0);
    if (fails + succ >= 20 && fails / (fails + succ) > 0.3) warnings.push({ code: "qr_failure_rate", message: `${Math.round((fails / (fails + succ)) * 100)}% of QR scans are failing.` });
    return {
      generatedAt: at.toISOString(),
      registered: week.registered,
      wap: week.wap,
      wapPercent: week.wapPercent,
      weekKey: week.weekKey,
      activeOrganizers: week.organizersPostingWeekly,
      eventsThisWeek: week.eventsPostedWeekly,
      eventsNext7Days: upcoming.size,
      eventsTodayTomorrow,
      rsvpsThisWeek: week.weekRsvps,
      checkinsThisWeek: week.weekCheckins,
      rsvpToAttendance: conv,
      retention: ret,
      survey,
      economy: { coinsEarnedMonth, coinsRedeemedMonth, outstanding, redeemableInventoryCoins: redeemableCoins, redeemableInventoryValue: redeemableValue, avgWeeklyEarnPerUser: Math.round(eh.avgWeeklyEarnPerUser * 10) / 10, redemptionRate: rr, earnedToRedeemableRatio: Math.round(eh.earnedToRedeemableRatio * 100) / 100, thresholds: campus.pilot.economyHealth },
      qr: { scanFailures: fails, scanSuccesses: succ },
      pendingReview,
      pendingRoleRequests: pendingRoles,
      scorecard,
      buzzScore: buzz,
      targets: campus.pilot.targets,
      warnings,
      daily: daily.docs.map((d) => d.data()).reverse(),
    };
  }),
);

/** Snapshots this week's scorecard into pilot_metrics for trend history. Runs weekly (Mon 03:00 IST). */
export const calculatePilotScorecard = onSchedule({ ...scheduleOpts, schedule: "0 3 * * 1", timeZone: "Asia/Kolkata" }, async () => {
  const campuses = await db.collection(COL.campuses).where("status", "==", "active").get();
  for (const c of campuses.docs) {
    const campus = normalizeCampus(c.id, c.data());
    const at = addDays(new Date(), -1); // snapshot the week that just ended
    const [week, conv, survey, ret] = await Promise.all([campusWeekStats(campus, at), conversionLast30(campus.id, at), latestSurvey(campus.id), retention(campus, at)]);
    const rows = buildScorecard({ registeredStudents: week.registered, wapPercent: week.wapPercent, week6Retention: ret.participation, organizersPostingWeekly: week.organizersPostingWeekly, rsvpToAttendance: conv.events > 0 ? conv.pct : null, nps: survey.nps, wouldMiss: survey.wouldMiss }, campus.pilot.bands);
    await db.collection(COL.pilotMetrics).doc(ids.pilotMetrics(campus.id, week.weekKey)).set({ campusId: campus.id, weekKey: week.weekKey, rows, raw: { ...week, conversion: conv, survey: { nps: survey.nps, wouldMiss: survey.wouldMiss, responses: survey.responses }, retention: ret }, computedAt: serverTs() });
  }
});

/* ------------------------------------------------------------------ */
/* Organizer analytics                                                 */
/* ------------------------------------------------------------------ */

export const getOrganizerEventAnalytics = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const eventId = str(req.data?.eventId, "eventId");
    const snap = await db.collection(COL.events).doc(eventId).get();
    if (!snap.exists) fail("not_found");
    const ev = snap.data()!;
    const m = await requireMembership(actor, ev.campusId, ["organizer", "campus_admin"]);
    if (!canManageEvent(m, actor.uid, ev)) fail("permission_denied", "You don't have access to this event.");
    const [opens, impressions, feedback, checkins, tribes] = await Promise.all([
      db.collection(COL.analyticsEvents).where("event", "==", "event_opened").where("eventId", "==", eventId).select("uid").get(),
      countWhere(db.collection(COL.analyticsEvents).where("event", "==", "event_impression").where("eventId", "==", eventId)),
      db.collection(COL.eventFeedback).where("eventId", "==", eventId).where("status", "==", "published").orderBy("at", "desc").limit(100).get(),
      db.collection(COL.checkins).where("eventId", "==", eventId).select("uid", "method", "at").get(),
      db.collection(COL.tribes).where("campusId", "==", ev.campusId).select("name").get(),
    ]);
    const uniqueOpens = new Set(opens.docs.map((d) => d.get("uid"))).size;
    const stats = ev.stats ?? {};
    // Repeat attendees: checked-in users who attended ≥1 other event from this club.
    const uids = checkins.docs.map((d) => d.get("uid") as string);
    let repeat = 0;
    if (uids.length > 0) {
      const club = await db.collection(COL.checkins).where("clubId", "==", ev.clubId).select("uid", "eventId").get();
      const counts = new Map<string, number>();
      club.docs.forEach((d) => counts.set(d.get("uid"), (counts.get(d.get("uid")) ?? 0) + 1));
      repeat = repeatAttendeeRate(uids.map((u) => counts.get(u) ?? 1));
    }
    const tribeNames = new Map(tribes.docs.map((d) => [d.id, d.get("name") as string]));
    const tribeBreakdown = Object.entries(ev.tribeCheckins ?? {}).map(([id, n]) => ({ tribeId: id, name: tribeNames.get(id) ?? id, checkins: n as number, rsvps: (ev.tribeRsvps ?? {})[id] ?? 0 })).sort((a, b) => b.checkins - a.checkins);
    const anonymousDefault = feedback.docs.map((d) => ({ id: d.id, rating: d.get("rating"), review: d.get("review"), displayName: d.get("anonymous") ? null : d.get("displayName"), at: tsToMs(d.get("at")) }));
    const themes = topWords(feedback.docs.map((d) => String(d.get("review") ?? "")));
    return {
      impressions,
      uniqueOpens,
      rsvps: stats.rsvpCount ?? 0,
      waitlist: stats.waitlistCount ?? 0,
      checkins: stats.checkinCount ?? 0,
      manualCheckins: stats.manualCheckinCount ?? 0,
      conversion: { discovery: percent(stats.rsvpCount ?? 0, uniqueOpens), attendance: rsvpToAttendance(stats.checkinCount ?? 0, stats.rsvpCount ?? 0) },
      repeatAttendeeRate: repeat,
      rating: { avg: stats.ratingAvg ?? 0, count: stats.feedbackCount ?? 0, distribution: stats.ratingDist ?? {} },
      tribeBreakdown,
      feedback: anonymousDefault,
      themes,
      checkinTimeline: bucketTimeline(checkins.docs.map((d) => tsToMs(d.get("at")) ?? 0)),
    };
  }),
);

/** Club-level analytics v2: trends, best categories, day/time patterns, acquisition. Premium adds a longer window. */
export const getClubAnalytics = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const clubId = str(req.data?.clubId, "clubId");
    const club = await db.collection(COL.clubs).doc(clubId).get();
    if (!club.exists) fail("not_found");
    const m = await requireMembership(actor, club.get("campusId"), ["organizer", "campus_admin"]);
    if (!m.roles.includes("campus_admin") && !(m.clubIds ?? []).includes(clubId)) fail("permission_denied", "You don't have access to this organizer account.");
    const ent = await db.collection(COL.entitlements).doc(`club:${clubId}:organizer_premium`).get();
    const premium = ent.exists && ent.get("status") === "active" && (!ent.get("validUntil") || (tsToMs(ent.get("validUntil")) ?? 0) > Date.now());
    const windowDays = premium ? 365 : 90;
    const since = Timestamp.fromDate(addDays(new Date(), -windowDays));
    const events = await db.collection(COL.events).where("clubId", "==", clubId).where("startAt", ">=", since).orderBy("startAt").get();
    const campus = await loadCampus(club.get("campusId"));
    const byTag: Record<string, { events: number; checkins: number; rsvps: number }> = {};
    const byDay: Record<string, { events: number; checkins: number }> = {};
    const byHour: Record<string, { events: number; checkins: number }> = {};
    const trend: Array<{ eventId: string; title: string; startAt: number; rsvps: number; checkins: number; rating: number }> = [];
    let totalRsvps = 0, totalCheckins = 0;
    const sources: Record<string, number> = {};
    for (const d of events.docs) {
      const s = d.get("stats") ?? {};
      totalRsvps += s.rsvpCount ?? 0; totalCheckins += s.checkinCount ?? 0;
      trend.push({ eventId: d.id, title: d.get("title"), startAt: tsToMs(d.get("startAt"))!, rsvps: s.rsvpCount ?? 0, checkins: s.checkinCount ?? 0, rating: s.ratingAvg ?? 0 });
      for (const t of [...(d.get("tags") ?? []), ...(d.get("tribeIds") ?? [])]) { byTag[t] = byTag[t] ?? { events: 0, checkins: 0, rsvps: 0 }; byTag[t].events++; byTag[t].checkins += s.checkinCount ?? 0; byTag[t].rsvps += s.rsvpCount ?? 0; }
      const lp = new Date(tsToMs(d.get("startAt"))!);
      const parts = new Intl.DateTimeFormat("en-US", { timeZone: campus.timezone, weekday: "short", hour: "numeric", hourCycle: "h23" }).formatToParts(lp);
      const wd = parts.find((p) => p.type === "weekday")?.value ?? "?"; const hr = parts.find((p) => p.type === "hour")?.value ?? "?";
      byDay[wd] = byDay[wd] ?? { events: 0, checkins: 0 }; byDay[wd].events++; byDay[wd].checkins += s.checkinCount ?? 0;
      byHour[hr] = byHour[hr] ?? { events: 0, checkins: 0 }; byHour[hr].events++; byHour[hr].checkins += s.checkinCount ?? 0;
    }
    if (premium && events.size > 0) {
      const rs = await db.collection(COL.rsvps).where("eventId", "in", events.docs.slice(0, 30).map((d) => d.id)).select("source").get();
      rs.docs.forEach((d) => { const k = d.get("source") ?? "unknown"; sources[k] = (sources[k] ?? 0) + 1; });
    }
    const attendeeCounts = new Map<string, number>();
    const cks = await db.collection(COL.checkins).where("clubId", "==", clubId).select("uid").get();
    cks.docs.forEach((d) => attendeeCounts.set(d.get("uid"), (attendeeCounts.get(d.get("uid")) ?? 0) + 1));
    const bestCategories = Object.entries(byTag).map(([tag, v]) => ({ tag, ...v, avgCheckins: Math.round((v.checkins / v.events) * 10) / 10 })).sort((a, b) => b.avgCheckins - a.avgCheckins).slice(0, 8);
    const recommendedSlots = Object.entries(byDay).filter(([, v]) => v.events >= 2).map(([day, v]) => ({ day, avgCheckins: Math.round((v.checkins / v.events) * 10) / 10 })).sort((a, b) => b.avgCheckins - a.avgCheckins).slice(0, 3);
    return { premium, windowDays, events: events.size, totalRsvps, totalCheckins, conversion: rsvpToAttendance(totalCheckins, totalRsvps), repeatAttendeeRate: repeatAttendeeRate([...attendeeCounts.values()]), uniqueAttendees: attendeeCounts.size, trend, bestCategories, byDay, byHour, recommendedSlots, acquisitionSources: premium ? sources : null };
  }),
);

/** Institutional analytics (student affairs) gated by campus_analytics entitlement. */
export const getInstitutionalAnalytics = onCall(
  { ...callableOpts, timeoutSeconds: 120 },
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const campus = await loadCampus(campusId);
    if (!campus.featureFlags.institutional_analytics_enabled) fail("feature_disabled");
    const ent = await db.collection(COL.entitlements).doc(`campus:${campusId}:campus_analytics`).get();
    const licensed = ent.exists && ent.get("status") === "active";
    if (!licensed) fail("permission_denied", "Institutional analytics requires a campus licence. Contact CampusBuzz.");
    const since = Timestamp.fromDate(addDays(new Date(), -Number(req.data?.days ?? 90)));
    const [daily, checkins, events, tribes, clubs] = await Promise.all([
      db.collection(COL.metricsDaily).where("campusId", "==", campusId).where("date", ">=", localDateKey(since.toDate(), campus.timezone)).orderBy("date").get(),
      db.collection(COL.checkins).where("campusId", "==", campusId).where("at", ">=", since).select("uid", "tribeIds", "clubId", "tags").get(),
      db.collection(COL.events).where("campusId", "==", campusId).where("startAt", ">=", since).select("clubId", "status", "stats", "tags").get(),
      db.collection(COL.tribes).where("campusId", "==", campusId).select("name").get(),
      db.collection(COL.clubs).where("campusId", "==", campusId).select("name").get(),
    ]);
    const tribeNames = new Map(tribes.docs.map((d) => [d.id, d.get("name") as string]));
    const clubNames = new Map(clubs.docs.map((d) => [d.id, d.get("name") as string]));
    const perUser = new Map<string, number>();
    const byTribe: Record<string, number> = {}; const byClub: Record<string, number> = {}; const byCategory: Record<string, number> = {};
    checkins.docs.forEach((d) => { perUser.set(d.get("uid"), (perUser.get(d.get("uid")) ?? 0) + 1); for (const t of d.get("tribeIds") ?? []) byTribe[t] = (byTribe[t] ?? 0) + 1; byClub[d.get("clubId")] = (byClub[d.get("clubId")] ?? 0) + 1; for (const t of d.get("tags") ?? []) byCategory[t] = (byCategory[t] ?? 0) + 1; });
    const dist = { "1": 0, "2-3": 0, "4-6": 0, "7+": 0 } as Record<string, number>;
    perUser.forEach((n) => { dist[n === 1 ? "1" : n <= 3 ? "2-3" : n <= 6 ? "4-6" : "7+"]++; });
    let rsvps = 0, cks = 0; events.docs.forEach((d) => { rsvps += d.get("stats.rsvpCount") ?? 0; cks += d.get("stats.checkinCount") ?? 0; });
    return {
      licensed: true,
      uniqueParticipants: perUser.size,
      totalCheckins: checkins.size,
      eventSupply: events.size,
      activeClubs: Object.keys(byClub).length,
      rsvpToAttendance: rsvpToAttendance(cks, rsvps),
      repeatAttendance: repeatAttendeeRate([...perUser.values()]),
      participationByTribe: Object.entries(byTribe).map(([id, n]) => ({ id, name: tribeNames.get(id) ?? id, checkins: n })).sort((a, b) => b.checkins - a.checkins),
      clubActivity: Object.entries(byClub).map(([id, n]) => ({ id, name: clubNames.get(id) ?? id, checkins: n })).sort((a, b) => b.checkins - a.checkins),
      participationByCategory: Object.entries(byCategory).map(([tag, n]) => ({ tag, checkins: n })).sort((a, b) => b.checkins - a.checkins).slice(0, 15),
      participationDistribution: dist,
      trend: daily.docs.map((d) => ({ date: d.get("date"), wap: d.get("wap"), wapPercent: d.get("wapPercent"), checkins: d.get("checkins"), events: d.get("events"), registered: d.get("registered") })),
      note: "These metrics are derived from verified check-ins and can support institutional reporting; CampusBuzz does not claim NAAC/NIRF certification.",
    };
  }),
);

function topWords(reviews: string[]): Array<{ word: string; count: number }> {
  if (reviews.length < 3) return [];
  const stop = new Set(["the", "and", "was", "for", "with", "that", "this", "very", "but", "not", "have", "had", "were", "are", "you", "all", "too", "its", "it's", "our", "they", "just", "more", "from"]);
  const counts = new Map<string, number>();
  for (const r of reviews) for (const w of r.toLowerCase().replace(/[^a-z\s]/g, " ").split(/\s+/)) if (w.length > 3 && !stop.has(w)) counts.set(w, (counts.get(w) ?? 0) + 1);
  return [...counts.entries()].filter(([, c]) => c >= 2).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([word, count]) => ({ word, count }));
}

function bucketTimeline(msList: number[]): Array<{ minute: number; count: number }> {
  if (msList.length === 0) return [];
  const min = Math.min(...msList);
  const buckets = new Map<number, number>();
  for (const ms of msList) { const b = Math.floor((ms - min) / 300000) * 5; buckets.set(b, (buckets.get(b) ?? 0) + 1); }
  return [...buckets.entries()].sort((a, b) => a[0] - b[0]).map(([minute, count]) => ({ minute, count }));
}
