import { onCall } from "firebase-functions/v2/https";
import { COL, ids } from "../config/collections";
import { fail } from "../domain/errors";
import { writeAudit } from "../lib/audit";
import { callableHandler, num, requireAuth, requireMembership, str } from "../lib/auth";
import { db, forEachPage, inc, serverTs, Timestamp, toDate } from "../lib/firestore";
import { enqueueNotification } from "../lib/notifications";
import { callableOpts } from "../lib/options";

const WOULD_MISS = ["strongly_yes", "yes", "unsure", "no"];

/** Campus admin creates a pilot survey (NPS + would-miss + open questions), optionally notifying everyone. */
export const createSurvey = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const campusId = str(req.data?.campusId, "campusId");
    await requireMembership(actor, campusId, ["campus_admin"]);
    const title = str(req.data?.title, "title", { max: 100 });
    const closesAt = toDate(req.data?.closesAt);
    const notify = req.data?.notify === true;
    const ref = db.collection(COL.surveys).doc();
    await ref.set({ campusId, title, status: "open", closesAt: closesAt ? Timestamp.fromDate(closesAt) : null, questions: ["love", "annoys", "wouldMiss", "helpedAttend", "nps"], createdAt: serverTs(), createdBy: actor.uid, stats: { responses: 0 } });
    writeAudit({ actorUid: actor.uid, action: "survey.create", entityType: "survey", entityId: ref.id, campusId, after: { title } });
    let queued = 0;
    if (notify) {
      await forEachPage(db.collection(COL.memberships).where("campusId", "==", campusId).where("status", "==", "active"), 300, async (docs) => {
        for (const m of docs) if ((await enqueueNotification({ uid: m.get("uid"), campusId, category: "engagement", title: "60 seconds to shape CampusBuzz", body: title, route: `/surveys/${ref.id}`, dedupeKey: `survey:${ref.id}:${m.get("uid")}` })) === "queued") queued++;
      });
    }
    return { surveyId: ref.id, queued };
  }),
);

export const submitSurveyResponse = onCall(
  callableOpts,
  callableHandler(async (req) => {
    const actor = await requireAuth(req);
    const surveyId = str(req.data?.surveyId, "surveyId");
    const survey = await db.collection(COL.surveys).doc(surveyId).get();
    if (!survey.exists) fail("not_found");
    await requireMembership(actor, survey.get("campusId"));
    if (survey.get("status") !== "open") fail("invalid_argument", "This survey has closed.");
    const a = req.data?.answers ?? {};
    const answers = {
      love: str(a.love, "love", { optional: true, max: 500 }),
      annoys: str(a.annoys, "annoys", { optional: true, max: 500 }),
      wouldMiss: WOULD_MISS.includes(a.wouldMiss) ? a.wouldMiss : fail("invalid_argument", "Answer whether you'd miss CampusBuzz."),
      helpedAttend: a.helpedAttend === true,
      nps: num(a.nps, "nps", { min: 0, max: 10, int: true }),
    };
    const ref = db.collection(COL.surveyResponses).doc(ids.surveyResponse(surveyId, actor.uid));
    await db.runTransaction(async (tx) => {
      const prev = await tx.get(ref);
      if (prev.exists) fail("already_submitted", "You've already answered this survey. Thanks!");
      tx.set(ref, { surveyId, uid: actor.uid, campusId: survey.get("campusId"), answers, at: serverTs() });
      tx.update(survey.ref, { "stats.responses": inc(1) });
    });
    return { ok: true };
  }),
);
