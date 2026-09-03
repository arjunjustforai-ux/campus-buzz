import { beforeAll, describe, expect, it } from "vitest";
import { COL, ids } from "../../src/config/collections";
import { signToken, windowIndex } from "../../src/domain/qrToken";
import { qrSigningSecret } from "../../src/config/secrets";
import { db, Timestamp } from "../../src/lib/firestore";
import { asUser, balance, expectDomainError, ledgerSum, makeCampus, makeEvent, makeUser } from "./fixtures";
import { cancelRsvp, createRsvp } from "../../src/handlers/rsvp";
import { checkInWithQr, issueEventQrToken, manualCheckIn, startEventCheckin } from "../../src/handlers/checkin";
import { submitEventFeedback } from "../../src/handlers/feedback";
import { closeEvent } from "../../src/handlers/events";
import { applyReferral } from "../../src/handlers/auth";
import { isoWeekKey, previousWeekKey } from "../../src/domain/time";

const C = "campus-part";

describe("RSVP", () => {
  beforeAll(async () => {
    await makeCampus(C);
    await makeUser(C, `${C}-org`, ["student", "organizer"]);
    for (const u of ["a", "b", "c"]) await makeUser(C, `${C}-${u}`);
  });

  it("awards +5 exactly once, even after cancel and re-RSVP", async () => {
    await makeEvent(C, "ev-rsvp");
    const r1 = await createRsvp.run(asUser(`${C}-a`, undefined, { eventId: "ev-rsvp", source: "feed" }));
    expect(r1).toMatchObject({ status: "confirmed", coinsAwarded: 5 });
    await expectDomainError(createRsvp.run(asUser(`${C}-a`, undefined, { eventId: "ev-rsvp" })), "already_rsvped");
    await cancelRsvp.run(asUser(`${C}-a`, undefined, { eventId: "ev-rsvp" }));
    const r2 = await createRsvp.run(asUser(`${C}-a`, undefined, { eventId: "ev-rsvp" }));
    expect(r2).toMatchObject({ status: "confirmed", coinsAwarded: 0 });
    expect(await balance(`${C}-a`)).toBe(5);
    expect(await ledgerSum(`${C}-a`)).toBe(5);
    const ev = await db.collection(COL.events).doc("ev-rsvp").get();
    expect(ev.get("stats.rsvpCount")).toBe(1);
  });

  it("enforces capacity and waitlists when enabled", async () => {
    await makeEvent(C, "ev-cap", { capacity: 1, waitlist: true });
    expect((await createRsvp.run(asUser(`${C}-a`, undefined, { eventId: "ev-cap" })) as any).status).toBe("confirmed");
    expect((await createRsvp.run(asUser(`${C}-b`, undefined, { eventId: "ev-cap" })) as any).status).toBe("waitlisted");
    // cancelling the confirmed RSVP promotes the waitlisted one
    await cancelRsvp.run(asUser(`${C}-a`, undefined, { eventId: "ev-cap" }));
    const b = await db.collection(COL.rsvps).doc(ids.rsvp("ev-cap", `${C}-b`)).get();
    expect(b.get("status")).toBe("confirmed");
    await makeEvent(C, "ev-full", { capacity: 1, waitlist: false });
    await createRsvp.run(asUser(`${C}-a`, undefined, { eventId: "ev-full" }));
    await expectDomainError(createRsvp.run(asUser(`${C}-c`, undefined, { eventId: "ev-full" })), "event_full");
  });

  it("rejects cancelled events and other campuses", async () => {
    await makeEvent(C, "ev-cancelled", { status: "cancelled" });
    await expectDomainError(createRsvp.run(asUser(`${C}-a`, undefined, { eventId: "ev-cancelled" })), "event_cancelled");
    await makeCampus("campus-other");
    await makeEvent("campus-other", "ev-other");
    await expectDomainError(createRsvp.run(asUser(`${C}-a`, undefined, { eventId: "ev-other" })), "permission_denied");
  });
});

describe("QR check-in", () => {
  const org = `${C}-org`;
  beforeAll(async () => {
    await makeCampus(C);
    await makeUser(C, org, ["student", "organizer"]);
    for (const u of ["q1", "q2", "q3", "ref"]) await makeUser(C, `${C}-${u}`);
  });

  async function liveEvent(id: string) {
    await makeEvent(C, id, { startInMinutes: 5, organizerUid: org });
    await startEventCheckin.run(asUser(org, undefined, { eventId: id }));
    const t = (await issueEventQrToken.run(asUser(org, undefined, { eventId: id }))) as any;
    return t.token as string;
  }

  it("verified scan awards +20 once; duplicate scan is idempotent", async () => {
    const token = await liveEvent("ev-qr");
    const r = (await checkInWithQr.run(asUser(`${C}-q1`, undefined, { token }))) as any;
    expect(r).toMatchObject({ coins: 20, streak: 1, multiplierApplied: false, alreadyCheckedIn: false });
    expect(r.certificateRef).toMatch(/^CB-/);
    const again = (await checkInWithQr.run(asUser(`${C}-q1`, undefined, { token }))) as any;
    expect(again).toMatchObject({ coins: 0, alreadyCheckedIn: true });
    expect(await balance(`${C}-q1`)).toBe(20);
    const ev = await db.collection(COL.events).doc("ev-qr").get();
    expect(ev.get("stats.checkinCount")).toBe(1);
    const stats = await db.collection(COL.participationStats).doc(`${C}-q1`).get();
    expect(stats.get("streak")).toBe(1);
    expect(stats.get("totalCheckins")).toBe(1);
  });

  it("rejects expired, tampered and stale-session tokens", async () => {
    await liveEvent("ev-qr2");
    const secret = qrSigningSecret();
    const session = await db.collection(COL.eventQrSessions).doc("ev-qr2").get();
    const old = signToken({ e: "ev-qr2", c: C, w: windowIndex(Date.now()) - 10, n: session.get("nonce"), v: 1 }, secret);
    await expectDomainError(checkInWithQr.run(asUser(`${C}-q2`, undefined, { token: old })), "qr_expired");
    await expectDomainError(checkInWithQr.run(asUser(`${C}-q2`, undefined, { token: "not.a.token" })), "qr_invalid");
    const forged = signToken({ e: "ev-qr2", c: C, w: windowIndex(Date.now()), n: session.get("nonce"), v: 1 }, "wrong-secret-xxxxxxxxxxxx");
    await expectDomainError(checkInWithQr.run(asUser(`${C}-q2`, undefined, { token: forged })), "qr_invalid");
    // Organizer restarts → nonce rotates → old-nonce tokens die.
    const stale = signToken({ e: "ev-qr2", c: C, w: windowIndex(Date.now()), n: "old-nonce", v: 1 }, secret);
    await expectDomainError(checkInWithQr.run(asUser(`${C}-q2`, undefined, { token: stale })), "qr_expired");
    expect(await balance(`${C}-q2`)).toBe(0);
    const failures = (await db.collection(COL.analyticsEvents).where("event", "==", "checkin_failure").where("uid", "==", `${C}-q2`).get()).size;
    expect(failures).toBeGreaterThanOrEqual(3);
  });

  it("refuses check-in when the organizer has not started it", async () => {
    await makeEvent(C, "ev-notstarted", { organizerUid: org });
    const secret = qrSigningSecret();
    const t = signToken({ e: "ev-notstarted", c: C, w: windowIndex(Date.now()), n: "x", v: 1 }, secret);
    await expectDomainError(checkInWithQr.run(asUser(`${C}-q2`, undefined, { token: t })), "qr_expired");
    await expectDomainError(issueEventQrToken.run(asUser(org, undefined, { eventId: "ev-notstarted" })), "checkin_not_active");
  });

  it("organizer-only token issuance", async () => {
    await liveEvent("ev-qr3");
    await expectDomainError(issueEventQrToken.run(asUser(`${C}-q3`, undefined, { eventId: "ev-qr3" })), "permission_denied");
    await expectDomainError(startEventCheckin.run(asUser(`${C}-q3`, undefined, { eventId: "ev-qr3" })), "permission_denied");
  });

  it("manual check-in is audited, idempotent and never double-awards after a QR scan", async () => {
    const token = await liveEvent("ev-manual");
    await checkInWithQr.run(asUser(`${C}-q3`, undefined, { token }));
    const m = (await manualCheckIn.run(asUser(org, undefined, { eventId: "ev-manual", uid: `${C}-q3`, reason: "phone died" }))) as any;
    expect(m.alreadyCheckedIn).toBe(true);
    const m2 = (await manualCheckIn.run(asUser(org, undefined, { eventId: "ev-manual", uid: `${C}-q2`, reason: "phone died" }))) as any;
    expect(m2).toMatchObject({ coins: 20, alreadyCheckedIn: false });
    const m3 = (await manualCheckIn.run(asUser(org, undefined, { eventId: "ev-manual", uid: `${C}-q2`, reason: "again" }))) as any;
    expect(m3.alreadyCheckedIn).toBe(true);
    expect(await balance(`${C}-q2`)).toBe(20);
    const audit = await db.collection(COL.auditLogs).where("action", "==", "checkin.manual").where("entityId", "==", ids.checkin("ev-manual", `${C}-q2`)).get();
    expect(audit.size).toBe(1);
    const ci = await db.collection(COL.checkins).doc(ids.checkin("ev-manual", `${C}-q2`)).get();
    expect(ci.get("method")).toBe("manual");
    await expectDomainError(manualCheckIn.run(asUser(`${C}-q1`, undefined, { eventId: "ev-manual", uid: `${C}-q3` })), "permission_denied");
  });

  it("streak multiplier doubles the reward from week 3", async () => {
    const thisWeek = isoWeekKey(new Date(), "Asia/Kolkata");
    await db.collection(COL.participationStats).doc(`${C}-q2`).set({ streak: 2, lastWeekKey: previousWeekKey(thisWeek), multiplierActive: false }, { merge: true });
    const token = await liveEvent("ev-streak");
    const r = (await checkInWithQr.run(asUser(`${C}-q2`, undefined, { token }))) as any;
    expect(r).toMatchObject({ coins: 40, streak: 3, multiplierApplied: true });
  });

  it("referral reward is paid once on the referred student's first verified attendance", async () => {
    const referrer = `${C}-q1`;
    const referred = `${C}-ref`;
    const code = (await db.collection(COL.users).doc(referrer).get()).get("referralCode");
    await applyReferral.run(asUser(referred, undefined, { campusId: C, code }));
    await expectDomainError(applyReferral.run(asUser(referred, undefined, { campusId: C, code })), "already_referred");
    await expectDomainError(applyReferral.run(asUser(referrer, undefined, { campusId: C, code })), "self_referral");
    const before = await balance(referrer);
    const token = await liveEvent("ev-referral");
    const r = (await checkInWithQr.run(asUser(referred, undefined, { token }))) as any;
    expect(r.referralAwarded).toBe(25);
    expect(await balance(referrer)).toBe(before + 25);
    const token2 = await liveEvent("ev-referral2");
    await checkInWithQr.run(asUser(referred, undefined, { token: token2 }));
    expect(await balance(referrer)).toBe(before + 25); // not paid twice
    expect((await db.collection(COL.referrals).doc(referred).get()).get("rewardAwarded")).toBe(true);
  });
});

describe("Feedback + event closure", () => {
  const org = `${C}-org`;
  beforeAll(async () => {
    await makeCampus(C);
    await makeUser(C, org, ["student", "organizer"]);
    for (let i = 0; i < 11; i++) await makeUser(C, `${C}-f${i}`);
  });

  it("only checked-in attendees can review; +10 once", async () => {
    await makeEvent(C, "ev-fb", { startInMinutes: 5, organizerUid: org });
    await expectDomainError(submitEventFeedback.run(asUser(`${C}-f0`, undefined, { eventId: "ev-fb", rating: 5 })), "feedback_requires_checkin");
    await startEventCheckin.run(asUser(org, undefined, { eventId: "ev-fb" }));
    const t = (await issueEventQrToken.run(asUser(org, undefined, { eventId: "ev-fb" }))) as any;
    await checkInWithQr.run(asUser(`${C}-f0`, undefined, { token: t.token }));
    const r = (await submitEventFeedback.run(asUser(`${C}-f0`, undefined, { eventId: "ev-fb", rating: 4, review: "Solid." }))) as any;
    expect(r.coinsAwarded).toBe(10);
    await expectDomainError(submitEventFeedback.run(asUser(`${C}-f0`, undefined, { eventId: "ev-fb", rating: 5 })), "already_submitted");
    await expectDomainError(submitEventFeedback.run(asUser(`${C}-f0`, undefined, { eventId: "ev-fb", rating: 9 })), "invalid_argument");
    expect(await balance(`${C}-f0`)).toBe(30);
    const ev = await db.collection(COL.events).doc("ev-fb").get();
    expect(ev.get("stats.ratingAvg")).toBe(4);
    expect(ev.get("stats.feedbackCount")).toBe(1);
  });

  it("closing an event pays the organizer bonus once when ≥10 verified attendees", async () => {
    await makeEvent(C, "ev-close", { startInMinutes: 5, organizerUid: org });
    await startEventCheckin.run(asUser(org, undefined, { eventId: "ev-close" }));
    for (let i = 0; i < 9; i++) await manualCheckIn.run(asUser(org, undefined, { eventId: "ev-close", uid: `${C}-f${i}`, reason: "test" }));
    const first = (await closeEvent.run(asUser(org, undefined, { eventId: "ev-close" }))) as any;
    expect(first.organizerBonus).toBe(0);
    // Late correction: 10th attendee within the correction window.
    await manualCheckIn.run(asUser(org, undefined, { eventId: "ev-close", uid: `${C}-f9`, reason: "late" }));
    await db.collection(COL.events).doc("ev-close").update({ status: "published" }); // reopen for the test
    const second = (await closeEvent.run(asUser(org, undefined, { eventId: "ev-close" }))) as any;
    expect(second.organizerBonus).toBe(50);
    await db.collection(COL.events).doc("ev-close").update({ status: "published" });
    const third = (await closeEvent.run(asUser(org, undefined, { eventId: "ev-close" }))) as any;
    expect(third.organizerBonus).toBe(0);
    expect(await ledgerSum(org)).toBe(50);
    const jobs = await db.collection(COL.notificationJobs).where("category", "==", "post_event").get();
    expect(jobs.docs.some((d) => d.id.startsWith("feedback:ev-close:"))).toBe(true);
    const ev = await db.collection(COL.events).doc("ev-close").get();
    expect(ev.get("status")).toBe("completed");
    expect(ev.get("closedAt")).toBeInstanceOf(Timestamp);
  });
});
