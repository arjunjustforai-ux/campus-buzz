/**
 * CampusBuzz deterministic EMULATOR seed.
 *
 *   npm run seed            (repo root, with the emulators running)
 *
 * Emulator-only: refuses to run against anything but a `demo-` project (see
 * tools/emulatorEnv.ts). Works on Windows, macOS and Linux with no env setup.
 * Creates a JAGSoM-style demo campus, Tribes, clubs, organizers, 14 upcoming +
 * 10 past events, synthetic students, check-in history, feedback, rewards,
 * vendors, redemptions, a brand + quest, a survey and daily metrics.
 * All people are synthetic. Credentials below are for the local emulator only.
 */
// Must come first: points the Admin SDK at the emulator before it is constructed.
import "./emulatorEnv";
import { getAuth } from "firebase-admin/auth";
import { db, FieldValue, Timestamp } from "../src/lib/firestore";
import { COL, ids } from "../src/config/collections";
import { DEFAULT_ECONOMY, DEFAULT_FEATURE_FLAGS, DEFAULT_PILOT } from "../src/config/defaults";
import { searchTokens, referralCodeFor } from "../src/domain/search";
import { feedVariantFor } from "../src/domain/recommendation";
import { updateStreak, EMPTY_STREAK } from "../src/domain/streaks";
import { hourBucket, isoWeekKey, localParts } from "../src/domain/time";
import type { StreakState } from "../src/domain/types";

const PROJECT = process.env.GCLOUD_PROJECT!;
const auth = getAuth();

const CAMPUS_ID = "jagsom-demo";
const DOMAIN = process.env.SEED_CAMPUS_DOMAIN || "demo.campusbuzz.test";
const TZ = "Asia/Kolkata";
const PASSWORD = "CampusBuzz!123";
const NOW = new Date();

// Deterministic PRNG so every seed run produces the same data.
let seed = 20260903;
const rnd = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
const pick = <T,>(arr: T[]) => arr[Math.floor(rnd() * arr.length)];
const ts = (d: Date) => Timestamp.fromDate(d);
const hoursFromNow = (h: number) => new Date(NOW.getTime() + h * 3600000);
const daysAgo = (d: number, hour = 17) => { const x = new Date(NOW.getTime() - d * 86400000); x.setUTCHours(hour - 5, 30, 0, 0); return x; };

interface Person { uid: string; email: string; name: string; roles: string[]; tribes: string[]; clubIds?: string[]; vendorId?: string; brandId?: string; superAdmin?: boolean }

const TRIBES = [
  { id: "finance-geeks", name: "Finance Geeks", emoji: "📈", color: "#CDFF57", description: "Markets, money, and the people who model them." },
  { id: "coders", name: "Coders", emoji: "💻", color: "#FF5F1F", description: "Hackathons, builds, and late-night debugging." },
  { id: "creatives", name: "Creatives", emoji: "🎨", color: "#FF8A5B", description: "Design, film, music, and everything made by hand." },
  { id: "sports-heads", name: "Sports Heads", emoji: "🏏", color: "#57D9FF", description: "Tournaments, fitness, and the noise from the field." },
  { id: "marketers", name: "Marketers", emoji: "📣", color: "#F6C945", description: "Brands, campaigns, and the psychology of attention." },
  { id: "debaters", name: "Debaters", emoji: "🎤", color: "#B085FF", description: "Model UN, moot courts, and winning the room." },
  { id: "social-impact", name: "Social Impact", emoji: "🌱", color: "#6BE38B", description: "Volunteering, sustainability, and doing good loudly." },
];

const CLUBS = [
  { id: "finance-club", name: "Finance & Investment Club", category: "academic", tribes: ["finance-geeks"] },
  { id: "coding-club", name: "Code Collective", category: "tech", tribes: ["coders"] },
  { id: "design-club", name: "Design Studio", category: "creative", tribes: ["creatives"] },
  { id: "sports-committee", name: "Sports Committee", category: "sports", tribes: ["sports-heads"] },
  { id: "marketing-club", name: "Brand Lab", category: "academic", tribes: ["marketers"] },
  { id: "debate-society", name: "Debate & MUN Society", category: "culture", tribes: ["debaters"] },
  { id: "impact-cell", name: "Social Impact Cell", category: "impact", tribes: ["social-impact"] },
  { id: "cultural-committee", name: "Cultural Committee", category: "culture", tribes: ["creatives", "marketers"] },
  { id: "entrepreneurship-cell", name: "E-Cell", category: "academic", tribes: ["finance-geeks", "marketers", "coders"] },
  { id: "film-society", name: "Film Society", category: "creative", tribes: ["creatives"] },
  { id: "consulting-club", name: "Consulting Club", category: "academic", tribes: ["finance-geeks", "debaters"] },
];

const FIRST = ["Aarav", "Priya", "Rohan", "Ananya", "Kabir", "Meera", "Vihaan", "Diya", "Arjun", "Sara", "Ishaan", "Nisha", "Aditya", "Riya", "Karan", "Tara", "Dev", "Zara", "Yash", "Pooja", "Rahul", "Sneha", "Nikhil", "Aisha", "Varun", "Kavya", "Siddharth", "Neha", "Aman", "Simran"];
const LAST = ["Sharma", "Iyer", "Menon", "Patel", "Reddy", "Nair", "Gupta", "Singh", "Rao", "Khan", "Bose", "Mehta", "Joshi", "Kulkarni", "Das", "Pillai", "Verma", "Chopra", "Shetty", "Malhotra"];

async function ensureUser(p: Person, opts: { onboarded?: boolean; createdAt?: Date } = {}) {
  try { await auth.getUser(p.uid); } catch { await auth.createUser({ uid: p.uid, email: p.email, password: PASSWORD, displayName: p.name, emailVerified: true }); }
  const createdAt = opts.createdAt ?? daysAgo(40);
  await db.collection(COL.users).doc(p.uid).set({
    uid: p.uid, email: p.email, displayName: p.name, avatarUrl: null, activeCampusId: CAMPUS_ID, campusIds: [CAMPUS_ID], tribeIds: p.tribes, primaryTribeId: p.tribes[0] ?? null,
    onboardingCompleted: opts.onboarded !== false, consentAcceptedAt: ts(createdAt), notificationPrefs: { transactional: true, reminders: true, engagement: true, postEvent: true },
    privacy: { showActivityToFriends: rnd() > 0.4, talentProfileOptIn: false, anonymousFeedback: false }, status: "active", referralCode: referralCodeFor(p.uid, p.name), feedVariant: feedVariantFor(p.uid),
    emailVerifiedAt: ts(createdAt), createdAt: ts(createdAt), updatedAt: ts(createdAt), superAdmin: p.superAdmin === true, fcmTokens: [],
  });
  await db.collection(COL.memberships).doc(ids.membership(CAMPUS_ID, p.uid)).set({ campusId: CAMPUS_ID, uid: p.uid, roles: p.roles, status: "active", clubIds: p.clubIds ?? [], requestedRoles: [], joinedAt: ts(createdAt), displayName: p.name, tribeIds: p.tribes, vendorId: p.vendorId ?? null, brandId: p.brandId ?? null, ...(p.roles.includes("organizer") ? { organizerApprovedAt: ts(createdAt) } : {}) });
  await db.collection(COL.participationStats).doc(p.uid).set({ uid: p.uid, campusId: CAMPUS_ID, streak: 0, lastWeekKey: null, multiplierActive: false, totalCheckins: 0, totalRsvps: 0, attendedTags: {}, attendedWeekdays: {}, attendedHourBuckets: {}, updatedAt: ts(createdAt) });
  await db.collection(COL.coinBalances).doc(p.uid).set({ uid: p.uid, campusId: CAMPUS_ID, balance: 0, lifetimeEarned: 0, lifetimeRedeemed: 0, lifetimeExpired: 0, updatedAt: ts(createdAt) });
}

async function credit(uid: string, key: string, reason: string, amount: number, refId: string, at: Date, meta: Record<string, unknown> = {}) {
  const ref = db.collection(COL.coinLedger).doc(key);
  if ((await ref.get()).exists) return;
  await ref.set({ key, uid, campusId: CAMPUS_ID, type: "credit", reason, amount, remaining: amount, refId, meta, economyVersion: 1, expiresAt: ts(new Date(at.getTime() + 90 * 86400000)), expired: false, createdAt: ts(at) });
  await db.collection(COL.coinBalances).doc(uid).set({ balance: FieldValue.increment(amount), lifetimeEarned: FieldValue.increment(amount), updatedAt: ts(at) }, { merge: true });
}

async function main() {
  console.log(`Seeding ${PROJECT} → campus ${CAMPUS_ID} (${DOMAIN})`);

  // Campus ---------------------------------------------------------------
  await db.collection(COL.campuses).doc(CAMPUS_ID).set({ name: "JAGSoM (Demo Campus)", shortName: "JAGSoM", domains: [DOMAIN], timezone: TZ, city: "Bengaluru", status: "active", economy: DEFAULT_ECONOMY, pilot: DEFAULT_PILOT, featureFlags: { ...DEFAULT_FEATURE_FLAGS, intercampus_events_enabled: true }, privacyPolicyUrl: "https://campusbuzz.app/privacy", termsUrl: "https://campusbuzz.app/terms", createdAt: ts(daysAgo(45)), updatedAt: ts(NOW), demo: true });
  await db.collection(COL.campuses).doc("northgate-demo").set({ name: "Northgate Institute (Demo Campus 2)", shortName: "Northgate", domains: ["northgate.campusbuzz.test"], timezone: TZ, city: "Pune", status: "active", economy: DEFAULT_ECONOMY, pilot: DEFAULT_PILOT, featureFlags: { ...DEFAULT_FEATURE_FLAGS, intercampus_events_enabled: true }, createdAt: ts(daysAgo(20)), updatedAt: ts(NOW), demo: true });
  await db.collection(COL.economyVersions).doc(ids.economyVersion(CAMPUS_ID, 1)).set({ campusId: CAMPUS_ID, ...DEFAULT_ECONOMY, changedBy: "seed", changedAt: ts(daysAgo(45)), noticeSent: false });
  await db.collection(COL.featureConfigs).doc(CAMPUS_ID).set({ campusId: CAMPUS_ID, flags: {}, recommendationWeights: {}, updatedAt: ts(NOW) });

  for (const [i, t] of TRIBES.entries()) await db.collection(COL.tribes).doc(t.id).set({ campusId: CAMPUS_ID, ...t, order: i, active: true, createdAt: ts(daysAgo(45)) });
  for (const { id, ...t } of TRIBES.slice(0, 5)) await db.collection(COL.tribes).doc(`ng-${id}`).set({ campusId: "northgate-demo", ...t, order: 0, active: true, createdAt: ts(daysAgo(20)) });

  // People ---------------------------------------------------------------
  const student: Person = { uid: "demo-student", email: `student@${DOMAIN}`, name: "Priya Sharma", roles: ["student"], tribes: ["finance-geeks", "coders", "debaters"] };
  const organizer: Person = { uid: "demo-organizer", email: `organizer@${DOMAIN}`, name: "Rohan Iyer", roles: ["student", "organizer"], tribes: ["finance-geeks", "marketers", "debaters"], clubIds: ["finance-club", "entrepreneurship-cell"] };
  const ambassador: Person = { uid: "demo-ambassador", email: `ambassador@${DOMAIN}`, name: "Ananya Menon", roles: ["student", "ambassador"], tribes: ["creatives", "marketers", "social-impact"] };
  const admin: Person = { uid: "demo-admin", email: `admin@${DOMAIN}`, name: "Dr. Kavya Rao (Campus Ops)", roles: ["student", "campus_admin"], tribes: ["social-impact", "debaters", "finance-geeks"] };
  const brand: Person = { uid: "demo-brand", email: `brand@${DOMAIN}`, name: "Nikhil Bose (FitFuel)", roles: ["student", "brand"], tribes: ["sports-heads", "marketers", "coders"], brandId: "fitfuel" };
  const vendor: Person = { uid: "demo-vendor", email: `vendor@${DOMAIN}`, name: "Campus Canteen Desk", roles: ["vendor"], tribes: ["finance-geeks", "coders", "creatives"], vendorId: "canteen" };
  const superAdmin: Person = { uid: "demo-superadmin", email: `superadmin@${DOMAIN}`, name: "CampusBuzz HQ", roles: ["student", "campus_admin"], tribes: ["coders", "finance-geeks", "marketers"], superAdmin: true };
  const named = [student, organizer, ambassador, admin, brand, vendor, superAdmin];
  for (const p of named) await ensureUser(p, { createdAt: daysAgo(42) });
  await db.collection(COL.memberships).doc(ids.membership("northgate-demo", superAdmin.uid)).set({ campusId: "northgate-demo", uid: superAdmin.uid, roles: ["student", "campus_admin"], status: "active", clubIds: [], requestedRoles: [], joinedAt: ts(daysAgo(20)), displayName: superAdmin.name, tribeIds: [] });

  // Club organizers (one per club) + 150 synthetic students.
  const clubOrganizers: Person[] = CLUBS.map((c, i) => ({ uid: `org-${c.id}`, email: `org.${c.id}@${DOMAIN}`, name: `${FIRST[(i * 3) % FIRST.length]} ${LAST[(i * 5) % LAST.length]}`, roles: ["student", "organizer"], tribes: [...new Set([...c.tribes, pick(TRIBES).id, pick(TRIBES).id])].slice(0, 3), clubIds: [c.id] }));
  for (const p of clubOrganizers) await ensureUser(p, { createdAt: daysAgo(41) });
  const students: Person[] = [];
  for (let i = 0; i < 150; i++) {
    const tribes = [...new Set([pick(TRIBES).id, pick(TRIBES).id, pick(TRIBES).id, pick(TRIBES).id])].slice(0, 3);
    while (tribes.length < 3) tribes.push(TRIBES[(i + tribes.length) % TRIBES.length].id);
    students.push({ uid: `stu-${String(i).padStart(3, "0")}`, email: `student${i}@${DOMAIN}`, name: `${FIRST[i % FIRST.length]} ${LAST[(i * 7) % LAST.length]}`, roles: ["student"], tribes });
  }
  for (const [i, p] of students.entries()) await ensureUser(p, { createdAt: daysAgo(40 - Math.floor(i / 5)) });
  const everyone = [student, ambassador, ...students];
  console.log(`users: ${named.length + clubOrganizers.length + students.length}`);

  // Clubs ----------------------------------------------------------------
  for (const c of CLUBS) await db.collection(COL.clubs).doc(c.id).set({ campusId: CAMPUS_ID, name: c.name, description: `${c.name} at JAGSoM — ${c.tribes.map((t) => TRIBES.find((x) => x.id === t)!.name).join(", ")}.`, category: c.category, logoUrl: null, adminUids: [`org-${c.id}`, ...(organizer.clubIds!.includes(c.id) ? [organizer.uid] : [])], status: "active", createdAt: ts(daysAgo(45)), updatedAt: ts(NOW), stats: { events: 0 } });
  await db.collection(COL.clubs).doc("ng-tech-club").set({ campusId: "northgate-demo", name: "Northgate Tech Society", category: "tech", adminUids: [superAdmin.uid], status: "active", createdAt: ts(daysAgo(20)), stats: { events: 0 } });

  // Events ---------------------------------------------------------------
  interface EventSpec { id: string; title: string; club: string; hoursFromNow: number; duration: number; location: string; capacity: number; tags: string[]; desc: string; participating?: string[] }
  const upcoming: EventSpec[] = [
    { id: "ev-finance-fest", title: "Finance Fest: Mock Trading Floor", club: "finance-club", hoursFromNow: 26, duration: 3, location: "Auditorium A", capacity: 120, tags: ["trading", "markets", "competition"], desc: "Ninety minutes on a simulated trading floor with live tickers. Teams of three. Winners get BuzzCoins and bragging rights for the semester." },
    { id: "ev-hack-night", title: "Build Night: Ship Something by Midnight", club: "coding-club", hoursFromNow: 30, duration: 5, location: "Innovation Lab, Block C", capacity: 60, tags: ["hackathon", "build", "coding"], desc: "Bring a laptop and an idea. Mentors on the floor from 7pm. Pizza at 9. Demo whatever works at midnight." },
    { id: "ev-poster-jam", title: "Poster Jam: Design the Fest Identity", club: "design-club", hoursFromNow: 50, duration: 2, location: "Studio 2", capacity: 40, tags: ["design", "workshop", "creative"], desc: "Two hours, one brief: the visual identity for this year's cultural fest. The winning system goes on every poster." },
    { id: "ev-cricket-finals", title: "Inter-Batch Cricket Finals", club: "sports-committee", hoursFromNow: 74, duration: 4, location: "Main Ground", capacity: 400, tags: ["cricket", "sports", "finals"], desc: "The final. Stands open at 3:30pm. Section 1 vs Section 4. Bring noise." },
    { id: "ev-brand-teardown", title: "Brand Teardown: Why Zomato Ads Work", club: "marketing-club", hoursFromNow: 52, duration: 1.5, location: "Seminar Hall 3", capacity: 80, tags: ["marketing", "brands", "talk"], desc: "A practitioner walks through three campaigns frame by frame. Q&A after." },
    { id: "ev-mun-prep", title: "MUN Prep: Crisis Committee Simulation", club: "debate-society", hoursFromNow: 100, duration: 3, location: "Room 204", capacity: 50, tags: ["mun", "debate", "simulation"], desc: "A full crisis committee run for delegates heading to the national MUN. Position papers due at the door." },
    { id: "ev-cleanup", title: "Lake Cleanup Drive", club: "impact-cell", hoursFromNow: 120, duration: 3, location: "Campus Lake (meet at Gate 2)", capacity: 100, tags: ["volunteering", "sustainability", "outdoor"], desc: "Gloves and bags provided. Verified attendance counts toward the Social Impact quest." },
    { id: "ev-open-mic", title: "Open Mic: Poetry, Comedy, Anything", club: "cultural-committee", hoursFromNow: 128, duration: 3, location: "Amphitheatre", capacity: 250, tags: ["open-mic", "music", "comedy", "culture"], desc: "Five minutes each. Sign-up sheet opens at the door. No heckling, that's the only rule." },
    { id: "ev-founder-talk", title: "Founder AMA: From Dorm to Series A", club: "entrepreneurship-cell", hoursFromNow: 150, duration: 1.5, location: "Auditorium B", capacity: 200, tags: ["startup", "talk", "founders"], desc: "An alum who raised a Series A last year answers everything. Moderated by the E-Cell." },
    { id: "ev-film-screening", title: "Film Society: Screening + Director Q&A", club: "film-society", hoursFromNow: 176, duration: 3, location: "Mini Theatre", capacity: 90, tags: ["film", "screening", "creative"], desc: "A festival short film followed by a conversation with its director over video call." },
    { id: "ev-case-comp", title: "Case Competition: Round 1", club: "consulting-club", hoursFromNow: 200, duration: 4, location: "Classrooms 301–305", capacity: 150, tags: ["consulting", "case", "competition"], desc: "Teams get the case at 9am and present at 1pm. Judges from two consulting firms." },
    { id: "ev-futsal", title: "5-a-side Futsal League Kickoff", club: "sports-committee", hoursFromNow: 224, duration: 3, location: "Futsal Court", capacity: 120, tags: ["futsal", "sports", "league"], desc: "Eight teams, four weeks, one trophy. Kickoff night doubles as the draw." },
    { id: "ev-excel-sprint", title: "Excel Sprint: Financial Modelling in 90 Minutes", club: "finance-club", hoursFromNow: 248, duration: 1.5, location: "Computer Lab 1", capacity: 45, tags: ["excel", "modelling", "workshop"], desc: "Build a three-statement model from a blank sheet. Laptops with Excel required." },
    { id: "ev-growth-jam", title: "Growth Jam: Pitch a Campaign in 10 Minutes", club: "marketing-club", hoursFromNow: 300, duration: 2, location: "Seminar Hall 1", capacity: 70, tags: ["marketing", "pitch", "competition"], desc: "Ten minutes, one brand, one audience. The E-Cell and Brand Lab co-host." },
    { id: "ev-intercampus-hack", title: "Inter-Campus Hack: JAGSoM × Northgate", club: "coding-club", hoursFromNow: 330, duration: 8, location: "Innovation Lab (JAGSoM) + remote", capacity: 150, tags: ["hackathon", "intercampus", "coding"], desc: "Both campuses, one leaderboard. Teams can be cross-campus.", participating: [CAMPUS_ID, "northgate-demo"] },
  ];
  const past: EventSpec[] = [
    { id: "past-1", title: "Orientation Mixer", club: "cultural-committee", hoursFromNow: -38 * 24, duration: 3, location: "Amphitheatre", capacity: 300, tags: ["mixer", "culture"], desc: "Where the semester started." },
    { id: "past-2", title: "Markets 101", club: "finance-club", hoursFromNow: -35 * 24, duration: 2, location: "Seminar Hall 3", capacity: 80, tags: ["markets", "workshop"], desc: "Intro session." },
    { id: "past-3", title: "Git & GitHub Bootcamp", club: "coding-club", hoursFromNow: -31 * 24, duration: 3, location: "Computer Lab 1", capacity: 50, tags: ["coding", "workshop"], desc: "Hands-on." },
    { id: "past-4", title: "Badminton Open", club: "sports-committee", hoursFromNow: -28 * 24, duration: 4, location: "Sports Hall", capacity: 64, tags: ["badminton", "sports"], desc: "Knockouts." },
    { id: "past-5", title: "Typography Night", club: "design-club", hoursFromNow: -24 * 24, duration: 2, location: "Studio 2", capacity: 40, tags: ["design", "creative"], desc: "Letters." },
    { id: "past-6", title: "Parliamentary Debate Trials", club: "debate-society", hoursFromNow: -21 * 24, duration: 3, location: "Room 204", capacity: 60, tags: ["debate"], desc: "Trials." },
    { id: "past-7", title: "Startup Pitch Night", club: "entrepreneurship-cell", hoursFromNow: -17 * 24, duration: 2.5, location: "Auditorium B", capacity: 200, tags: ["startup", "pitch"], desc: "Eight pitches." },
    { id: "past-8", title: "Brand Lab: Meme Marketing", club: "marketing-club", hoursFromNow: -14 * 24, duration: 1.5, location: "Seminar Hall 1", capacity: 80, tags: ["marketing", "talk"], desc: "Memes." },
    { id: "past-9", title: "Tree Plantation Drive", club: "impact-cell", hoursFromNow: -10 * 24, duration: 3, location: "North Lawn", capacity: 100, tags: ["volunteering", "sustainability"], desc: "Saplings." },
    { id: "past-10", title: "Valuation Masterclass", club: "finance-club", hoursFromNow: -7 * 24, duration: 2, location: "Seminar Hall 3", capacity: 80, tags: ["valuation", "workshop", "markets"], desc: "DCF." },
    { id: "past-11", title: "Weekend Futsal Friendly", club: "sports-committee", hoursFromNow: -3 * 24, duration: 2, location: "Futsal Court", capacity: 60, tags: ["futsal", "sports"], desc: "Friendly." },
    { id: "past-12", title: "UI Critique Circle", club: "design-club", hoursFromNow: -2 * 24, duration: 1.5, location: "Studio 2", capacity: 30, tags: ["design", "workshop"], desc: "Critique." },
  ];
  const allEvents = [...upcoming, ...past];
  for (const e of allEvents) {
    const club = CLUBS.find((c) => c.id === e.club)!;
    const start = hoursFromNow(e.hoursFromNow); const end = new Date(start.getTime() + e.duration * 3600000);
    const isPast = e.hoursFromNow < 0;
    await db.collection(COL.events).doc(e.id).set({
      campusId: CAMPUS_ID, hostCampusId: CAMPUS_ID, participatingCampusIds: e.participating ?? [CAMPUS_ID], clubId: club.id, clubName: club.name, organizerUid: `org-${club.id}`,
      title: e.title, description: e.desc, posterUrl: null, startAt: ts(start), endAt: ts(end), location: { name: e.location, address: "JAGSoM Campus, Bengaluru", lat: 12.9784, lng: 77.6408 }, capacity: e.capacity, waitlistEnabled: true,
      tribeIds: club.tribes, tags: e.tags, contact: `${club.name} desk`, registrationClosesAt: null, certificateEnabled: true,
      checkinOpensAt: ts(new Date(start.getTime() - 30 * 60000)), checkinClosesAt: ts(new Date(end.getTime() + 120 * 60000)), checkinActive: false,
      status: isPast ? "completed" : "published", publishedAt: ts(new Date(start.getTime() - 7 * 86400000)), reviewStatus: isPast || rnd() > 0.3 ? "approved" : "pending_review",
      stats: { rsvpCount: 0, waitlistCount: 0, checkinCount: 0, manualCheckinCount: 0, feedbackCount: 0, ratingSum: 0, ratingAvg: 0, ratingDist: {}, opens: 0, impressions: 0 }, tribeCheckins: {}, tribeRsvps: {}, organizerBonusAwarded: false,
      searchTokens: searchTokens(e.title, e.desc, club.name, ...e.tags), createdAt: ts(new Date(start.getTime() - 7 * 86400000)), updatedAt: ts(NOW), ...(isPast ? { closedAt: ts(new Date(end.getTime() + 2 * 3600000)), closedBy: "system" } : {}),
    });
  }
  console.log(`events: ${allEvents.length}`);

  // Participation history: RSVPs + check-ins on past events, RSVPs on upcoming.
  const streaks = new Map<string, StreakState>();
  const rsvpBatchOps: Array<() => Promise<void>> = [];
  let totalCheckins = 0;
  for (const e of allEvents) {
    const club = CLUBS.find((c) => c.id === e.club)!;
    const start = hoursFromNow(e.hoursFromNow); const end = new Date(start.getTime() + e.duration * 3600000);
    const isPast = e.hoursFromNow < 0;
    const affinity = everyone.filter((p) => p.tribes.some((t) => club.tribes.includes(t)));
    const others = everyone.filter((p) => !affinity.includes(p));
    const goers = [...affinity.filter(() => rnd() < 0.55), ...others.filter(() => rnd() < 0.12)].slice(0, e.capacity);
    if (e.id === "ev-finance-fest" || e.id === "past-10") { if (!goers.includes(student)) goers.unshift(student); }
    const evRef = db.collection(COL.events).doc(e.id);
    const tribeRsvps: Record<string, number> = {}; const tribeCheckins: Record<string, number> = {};
    let rsvpCount = 0, checkinCount = 0, manual = 0, feedbackCount = 0, ratingSum = 0; const ratingDist: Record<string, number> = {};
    for (const p of goers) {
      const rsvpAt = new Date(start.getTime() - (1 + rnd() * 5) * 86400000);
      rsvpCount++; for (const t of p.tribes) tribeRsvps[t] = (tribeRsvps[t] ?? 0) + 1;
      rsvpBatchOps.push(async () => {
        await db.collection(COL.rsvps).doc(ids.rsvp(e.id, p.uid)).set({ eventId: e.id, uid: p.uid, campusId: CAMPUS_ID, userCampusId: CAMPUS_ID, status: "confirmed", tribeIds: p.tribes, source: pick(["feed", "search", "share", "tribe_filter", "notification"]), createdAt: ts(rsvpAt), updatedAt: ts(rsvpAt), cancelledAt: null, startAt: ts(start), eventTitle: e.title });
        await credit(p.uid, ids.ledger.rsvp(e.id, p.uid), "rsvp", 5, e.id, rsvpAt);
        await db.collection(COL.participationStats).doc(p.uid).set({ totalRsvps: FieldValue.increment(1) }, { merge: true });
      });
      if (isPast && rnd() < 0.62) {
        const method = rnd() < 0.08 ? "manual" : "qr";
        const at = new Date(start.getTime() + rnd() * 40 * 60000);
        const prev = streaks.get(p.uid) ?? EMPTY_STREAK;
        const next = updateStreak(prev, at, TZ, DEFAULT_ECONOMY); streaks.set(p.uid, next);
        const mult = next.streak >= DEFAULT_ECONOMY.streakThresholdWeeks; const coins = mult ? 40 : 20;
        checkinCount++; if (method === "manual") manual++; for (const t of p.tribes) tribeCheckins[t] = (tribeCheckins[t] ?? 0) + 1;
        const lp = localParts(at, TZ);
        rsvpBatchOps.push(async () => {
          await db.collection(COL.checkins).doc(ids.checkin(e.id, p.uid)).set({ eventId: e.id, uid: p.uid, campusId: CAMPUS_ID, userCampusId: CAMPUS_ID, method, byUid: method === "manual" ? `org-${club.id}` : null, reason: method === "manual" ? "Camera not working" : null, tribeIds: p.tribes, coinsAwarded: coins, streakAtCheckin: next.streak, multiplierApplied: mult, certificateRef: `CB-${e.id.slice(0, 6).toUpperCase()}-${p.uid.slice(0, 6).toUpperCase()}`, eventTitle: e.title, clubId: club.id, tags: e.tags, eventTribeIds: club.tribes, startAt: ts(start), at: ts(at), weekKey: isoWeekKey(at, TZ) });
          await credit(p.uid, ids.ledger.checkin(e.id, p.uid), "checkin", coins, e.id, at, { method, multiplierApplied: mult, streak: next.streak });
          const tagInc: Record<string, unknown> = {}; for (const t of [...e.tags, ...club.tribes]) tagInc[`attendedTags.${t}`] = FieldValue.increment(1);
          await db.collection(COL.participationStats).doc(p.uid).set({ streak: next.streak, lastWeekKey: next.lastWeekKey, multiplierActive: next.multiplierActive, totalCheckins: FieldValue.increment(1), lastCheckinAt: ts(at), [`attendedWeekdays.${lp.weekday}`]: FieldValue.increment(1), [`attendedHourBuckets.${hourBucket(lp.hour)}`]: FieldValue.increment(1), ...tagInc }, { merge: true });
          if (method === "manual") await db.collection(COL.auditLogs).add({ actorUid: `org-${club.id}`, action: "checkin.manual", entityType: "checkin", entityId: ids.checkin(e.id, p.uid), campusId: CAMPUS_ID, reason: "Camera not working", before: null, after: { eventId: e.id, uid: p.uid, coins }, at: ts(at) });
        });
        if (rnd() < 0.5) {
          const rating = pick([5, 5, 4, 4, 4, 3, 5, 2]); feedbackCount++; ratingSum += rating; ratingDist[rating] = (ratingDist[rating] ?? 0) + 1;
          const fbAt = new Date(end.getTime() + (2 + rnd() * 20) * 3600000);
          const review = pick(["Loved the energy — more of this please.", "Great session, ran a bit long.", "Speaker was excellent, venue was cramped.", "Well organised. Would come again.", "Good but the sound system needs work.", "Best event this semester honestly.", null, null]);
          rsvpBatchOps.push(async () => {
            await db.collection(COL.eventFeedback).doc(ids.feedback(e.id, p.uid)).set({ eventId: e.id, uid: p.uid, campusId: CAMPUS_ID, clubId: club.id, rating, review, structured: {}, anonymous: rnd() < 0.3, displayName: p.name, status: "published", at: ts(fbAt) });
            await credit(p.uid, ids.ledger.feedback(e.id, p.uid), "feedback", 10, e.id, fbAt);
          });
        }
      }
    }
    if (isPast && checkinCount >= 10) rsvpBatchOps.push(async () => { await credit(`org-${club.id}`, ids.ledger.organizer(e.id), "organizer_bonus", 50, e.id, new Date(end.getTime() + 3 * 3600000), { verifiedAttendees: checkinCount }); });
    totalCheckins += checkinCount;
    await evRef.update({ "stats.rsvpCount": rsvpCount, "stats.checkinCount": checkinCount, "stats.manualCheckinCount": manual, "stats.feedbackCount": feedbackCount, "stats.ratingSum": ratingSum, "stats.ratingAvg": feedbackCount ? Math.round((ratingSum / feedbackCount) * 100) / 100 : 0, "stats.ratingDist": ratingDist, tribeRsvps, tribeCheckins, organizerBonusAwarded: isPast && checkinCount >= 10 });
    // Funnel analytics (impressions/opens) so organizer analytics have data.
    for (let i = 0; i < rsvpCount * 3; i++) rsvpBatchOps.push(async () => { await db.collection(COL.analyticsEvents).add({ event: i % 3 === 0 ? "event_opened" : "event_impression", uid: pick(everyone).uid, campusId: CAMPUS_ID, eventId: e.id, source: "feed", at: ts(new Date(start.getTime() - rnd() * 6 * 86400000)) }); });
  }
  for (let i = 0; i < rsvpBatchOps.length; i += 40) await Promise.all(rsvpBatchOps.slice(i, i + 40).map((f) => f()));
  console.log(`rsvps/checkins/feedback written; checkins=${totalCheckins}`);

  // Rewards, vendors, redemptions ------------------------------------------
  await db.collection(COL.vendors).doc("canteen").set({ campusId: CAMPUS_ID, name: "Main Canteen", contact: "canteen@jagsom.demo", settlementTerms: "Monthly, net 15", status: "active", createdAt: ts(daysAgo(40)), stats: { fulfilled: 0, pendingSettlementValue: 0 } });
  await db.collection(COL.vendors).doc("print-shop").set({ campusId: CAMPUS_ID, name: "Campus Print Shop", contact: "print@jagsom.demo", settlementTerms: "Monthly", status: "active", createdAt: ts(daysAgo(40)), stats: { fulfilled: 0, pendingSettlementValue: 0 } });
  await db.collection(COL.vendors).doc("merch-store").set({ campusId: CAMPUS_ID, name: "JAGSoM Merch Store", contact: "merch@jagsom.demo", settlementTerms: "Quarterly", status: "active", createdAt: ts(daysAgo(40)), stats: { fulfilled: 0, pendingSettlementValue: 0 } });
  const rewards = [
    { id: "rw-canteen-50", title: "₹50 Canteen Voucher", description: "Any item at the main canteen. Show the code at the counter.", type: "voucher", coinCost: 100, inventory: 120, faceValue: 50, vendorId: "canteen", redemptionInstructions: "Show your redemption code at the canteen desk." },
    { id: "rw-priority", title: "Priority Registration Pass", description: "Skip the queue for the next capacity-limited event.", type: "priority_access", coinCost: 75, inventory: 40, faceValue: 0, vendorId: null, redemptionInstructions: "Your pass is applied automatically at your next RSVP." },
    { id: "rw-print-50", title: "50 Pages Printing Credit", description: "Black & white printing at the campus print shop.", type: "printing_credit", coinCost: 80, inventory: 80, faceValue: 50, vendorId: "print-shop", redemptionInstructions: "Show the code at the print shop counter." },
    { id: "rw-tee", title: "CampusBuzz × JAGSoM Tee", description: "Limited run. Lime on black.", type: "merchandise", coinCost: 350, inventory: 25, faceValue: 499, vendorId: "merch-store", redemptionInstructions: "Collect from the merch store, Block A." },
    { id: "rw-hoodie", title: "Fest Hoodie", description: "The one everyone asks about.", type: "merchandise", coinCost: 500, inventory: 10, faceValue: 1299, vendorId: "merch-store", redemptionInstructions: "Collect from the merch store, Block A." },
    { id: "rw-cert", title: "Participation Certificate", description: "Free for any event you were verified at.", type: "certificate", coinCost: 0, inventory: null, faceValue: 0, vendorId: null, redemptionInstructions: "Generated from your participation history." },
  ];
  for (const r of rewards) await db.collection(COL.rewards).doc(r.id).set({ campusId: CAMPUS_ID, ...r, imageUrl: null, terms: "Non-transferable. No cash value. BuzzCoins expire 90 days after they are earned.", perUserLimit: r.type === "merchandise" ? 1 : 0, activeFrom: null, activeUntil: null, redemptionExpiryDays: 30, status: "active", stats: { redeemed: 0, fulfilled: 0 }, createdAt: ts(daysAgo(30)), updatedAt: ts(NOW) });
  // A few completed redemptions from students with enough balance.
  const balances = await db.collection(COL.coinBalances).where("campusId", "==", CAMPUS_ID).where("balance", ">=", 100).limit(30).get();
  let redemptions = 0;
  for (const b of balances.docs.slice(0, 18)) {
    const r = redemptions % 3 === 0 ? rewards[2] : rewards[0];
    const at = daysAgo(1 + (redemptions % 20), 13);
    const redId = `red-${String(redemptions).padStart(3, "0")}`;
    const fulfilled = redemptions % 4 !== 3;
    await db.collection(COL.coinLedger).doc(ids.ledger.redemption(redId)).set({ key: ids.ledger.redemption(redId), uid: b.id, campusId: CAMPUS_ID, type: "debit", reason: "redemption", amount: -r.coinCost, refId: redId, meta: { rewardId: r.id, title: r.title }, economyVersion: 1, fifoApplied: false, createdAt: ts(at) });
    await b.ref.set({ balance: FieldValue.increment(-r.coinCost), lifetimeRedeemed: FieldValue.increment(r.coinCost) }, { merge: true });
    await db.collection(COL.redemptions).doc(redId).set({ uid: b.id, campusId: CAMPUS_ID, rewardId: r.id, rewardTitle: r.title, rewardType: r.type, vendorId: r.vendorId, coinCost: r.coinCost, faceValue: r.faceValue, code: `DEMO-${String(1000 + redemptions)}`, status: fulfilled ? "fulfilled" : "issued", issuedAt: ts(at), expiresAt: ts(new Date(at.getTime() + 30 * 86400000)), fulfilledAt: fulfilled ? ts(new Date(at.getTime() + 3600000)) : null, fulfilledBy: fulfilled ? vendor.uid : null, settlementStatus: "pending", settlementMonth: fulfilled ? `${at.getUTCFullYear()}-${String(at.getUTCMonth() + 1).padStart(2, "0")}` : null, redemptionInstructions: r.redemptionInstructions });
    await db.collection(COL.rewards).doc(r.id).update({ inventory: FieldValue.increment(-1), "stats.redeemed": FieldValue.increment(1), ...(fulfilled ? { "stats.fulfilled": FieldValue.increment(1) } : {}) });
    if (fulfilled && r.vendorId) await db.collection(COL.vendors).doc(r.vendorId).update({ "stats.fulfilled": FieldValue.increment(1), "stats.pendingSettlementValue": FieldValue.increment(r.faceValue) });
    redemptions++;
  }
  console.log(`rewards: ${rewards.length}, redemptions: ${redemptions}`);

  // Referrals ------------------------------------------------------------
  for (let i = 0; i < 12; i++) {
    const referred = students[100 + i]; const referrer = i < 7 ? ambassador : student;
    const attended = (await db.collection(COL.checkins).where("uid", "==", referred.uid).limit(1).get());
    const awarded = !attended.empty;
    await db.collection(COL.referrals).doc(referred.uid).set({ referrerUid: referrer.uid, referredUid: referred.uid, campusId: CAMPUS_ID, code: referralCodeFor(referrer.uid, referrer.name), ambassador: referrer === ambassador, signupAt: ts(daysAgo(30 - i)), firstAttendanceAt: awarded ? attended.docs[0].get("at") : null, firstAttendanceEventId: awarded ? attended.docs[0].get("eventId") : null, rewardAwarded: awarded, signals: {} });
    await db.collection(COL.users).doc(referred.uid).set({ referredBy: referrer.uid }, { merge: true });
    if (awarded) await credit(referrer.uid, ids.ledger.referral(referred.uid), "referral", 25, referred.uid, new Date(attended.docs[0].get("at").toMillis()));
  }

  // Friends --------------------------------------------------------------
  const friendPairs: Array<[Person, Person, string]> = [[student, students[3], "accepted"], [student, students[8], "accepted"], [student, ambassador, "accepted"], [students[12], student, "pending"], [student, students[20], "pending"]];
  for (const [a, b, status] of friendPairs) await db.collection(COL.friendships).doc(ids.friendship(a.uid, b.uid)).set({ uids: [a.uid, b.uid].sort(), requesterUid: a.uid, campusId: CAMPUS_ID, status, createdAt: ts(daysAgo(10)), respondedAt: status === "accepted" ? ts(daysAgo(9)) : null, blockedBy: null });
  for (const uid of [students[3].uid, students[8].uid]) await db.collection(COL.users).doc(uid).set({ privacy: { showActivityToFriends: true, talentProfileOptIn: false, anonymousFeedback: false } }, { merge: true });

  // Brand + quests -------------------------------------------------------
  await db.collection(COL.brandAccounts).doc("fitfuel").set({ name: "FitFuel", status: "active", logoUrl: null, createdAt: ts(daysAgo(25)), updatedAt: ts(NOW) });
  await db.collection(COL.brandMemberships).doc(ids.brandMembership("fitfuel", brand.uid)).set({ brandId: "fitfuel", uid: brand.uid, status: "active", role: "brand", createdAt: ts(daysAgo(25)) });
  const questBase = { brandId: "fitfuel", creativeUrl: null, campusIds: [CAMPUS_ID], terms: "Open to verified JAGSoM students. One completion per student.", sponsorDisclosure: "Sponsored by FitFuel", participantLimit: 500, createdBy: brand.uid, createdAt: ts(daysAgo(20)), updatedAt: ts(NOW) };
  await db.collection(COL.quests).doc("quest-fitness-week").set({ ...questBase, title: "FitFuel Fitness Week", description: "Show up to any two sports events this month. Verified check-ins only.", tribeIds: ["sports-heads"], startAt: ts(daysAgo(14)), endAt: ts(hoursFromNow(14 * 24)), type: "event_count", criteria: { eventIds: [], count: 2, checklist: [], streakWeeks: 0, tagFilter: ["sports"] }, rewardCoins: 40, campaignValue: 25000, status: "live", financialStatus: "advance_received", approvedBy: admin.uid, approvedAt: ts(daysAgo(13)), submittedAt: ts(daysAgo(15)), stats: { views: 0, joins: 0, completions: 0, coinsDistributed: 0, campusBreakdown: {}, tribeBreakdown: {} } });
  await db.collection(COL.quests).doc("quest-productivity").set({ ...questBase, title: "FitFuel Productivity Challenge", description: "Attend a workshop and tell us one habit you're changing.", tribeIds: [], startAt: ts(hoursFromNow(48)), endAt: ts(hoursFromNow(30 * 24)), type: "checklist", criteria: { eventIds: [], count: 0, checklist: ["Attend any workshop", "Pick one habit to change", "Share it with your Tribe"], streakWeeks: 0, tagFilter: [] }, rewardCoins: 30, campaignValue: 15000, status: "submitted", financialStatus: "quoted", submittedAt: ts(daysAgo(1)), stats: { views: 0, joins: 0, completions: 0, coinsDistributed: 0, campusBreakdown: {}, tribeBreakdown: {} } });
  // Quest participation for fitness week from sports goers.
  const sportsCheckins = await db.collection(COL.checkins).where("campusId", "==", CAMPUS_ID).where("clubId", "==", "sports-committee").get();
  const byUid = new Map<string, number>(); sportsCheckins.docs.forEach((d) => byUid.set(d.get("uid"), (byUid.get(d.get("uid")) ?? 0) + 1));
  let joins = 0, completions = 0; const tribeBreakdown: Record<string, number> = {};
  for (const [uid, n] of byUid) {
    if (joins >= 60) break;
    const u = everyone.find((p) => p.uid === uid); if (!u || !u.tribes.includes("sports-heads")) continue;
    const completed = n >= 2; joins++;
    await db.collection(COL.questCompletions).doc(ids.questCompletion("quest-fitness-week", uid)).set({ questId: "quest-fitness-week", uid, campusId: CAMPUS_ID, tribeIds: u.tribes, status: completed ? "completed" : "joined", progress: { eventIds: sportsCheckins.docs.filter((d) => d.get("uid") === uid).map((d) => d.get("eventId")).slice(0, 2), checklist: [], count: Math.min(n, 2) }, joinedAt: ts(daysAgo(12)), completedAt: completed ? ts(daysAgo(3)) : null, coinsAwarded: completed ? 40 : 0, brandId: "fitfuel", questTitle: "FitFuel Fitness Week" });
    if (completed) { completions++; for (const t of u.tribes) tribeBreakdown[t] = (tribeBreakdown[t] ?? 0) + 1; await credit(uid, ids.ledger.quest("quest-fitness-week", uid), "quest", 40, "quest-fitness-week", daysAgo(3), { brandId: "fitfuel" }); }
  }
  await db.collection(COL.quests).doc("quest-fitness-week").update({ "stats.joins": joins, "stats.completions": completions, "stats.views": joins * 4, "stats.coinsDistributed": completions * 40, "stats.campusBreakdown": { [CAMPUS_ID]: { joins, completions } }, "stats.tribeBreakdown": tribeBreakdown });
  console.log(`quest joins=${joins} completions=${completions}`);

  // Entitlements ---------------------------------------------------------
  await db.collection(COL.entitlements).doc("club:finance-club:organizer_premium").set({ subjectType: "club", subjectId: "finance-club", key: "organizer_premium", status: "active", plan: "premium_monthly", billingStatus: "manual", validUntil: ts(hoursFromNow(60 * 24)), grantedBy: superAdmin.uid, createdAt: ts(daysAgo(10)), updatedAt: ts(daysAgo(10)) });
  await db.collection(COL.entitlements).doc(`campus:${CAMPUS_ID}:campus_analytics`).set({ subjectType: "campus", subjectId: CAMPUS_ID, key: "campus_analytics", status: "active", plan: "semester", billingStatus: "manual", validUntil: ts(hoursFromNow(120 * 24)), grantedBy: superAdmin.uid, createdAt: ts(daysAgo(10)), updatedAt: ts(daysAgo(10)) });
  await db.collection(COL.entitlements).doc("brand:fitfuel:brand_dashboard").set({ subjectType: "brand", subjectId: "fitfuel", key: "brand_dashboard", status: "active", plan: "campaign", billingStatus: "manual", validUntil: null, grantedBy: superAdmin.uid, createdAt: ts(daysAgo(20)), updatedAt: ts(daysAgo(20)) });

  // Survey + responses ---------------------------------------------------
  await db.collection(COL.surveys).doc("survey-week3").set({ campusId: CAMPUS_ID, title: "Week 3 pulse check", status: "open", closesAt: ts(hoursFromNow(14 * 24)), questions: ["love", "annoys", "wouldMiss", "helpedAttend", "nps"], createdAt: ts(daysAgo(6)), createdBy: admin.uid, stats: { responses: 0 } });
  let responses = 0;
  for (const p of students.slice(0, 48)) {
    const npsScore = pick([10, 9, 9, 8, 8, 7, 10, 6, 9, 5, 8, 10]);
    await db.collection(COL.surveyResponses).doc(ids.surveyResponse("survey-week3", p.uid)).set({ surveyId: "survey-week3", uid: p.uid, campusId: CAMPUS_ID, answers: { love: pick(["Finding events I'd never have heard about", "The QR check-in is fast", "BuzzCoins for the canteen", "Seeing what my Tribe is going to"]), annoys: pick(["Too few events on weekends", "Reminders could be earlier", "Want more rewards", ""]), wouldMiss: pick(["strongly_yes", "yes", "yes", "unsure", "no", "yes"]), helpedAttend: rnd() < 0.7, nps: npsScore }, at: ts(daysAgo(1 + (responses % 5))) });
    responses++;
  }
  await db.collection(COL.surveys).doc("survey-week3").update({ "stats.responses": responses });

  // Pending organizer request + a report + support request for the admin queues.
  await db.collection(COL.memberships).doc(ids.membership(CAMPUS_ID, students[5].uid)).set({ requestedRoles: ["organizer"], roleRequests: { organizer: { note: "I'm the new secretary of the Photography Club.", clubName: "Photography Club", requestedAt: ts(daysAgo(1)), status: "pending" } } }, { merge: true });
  await db.collection(COL.reports).doc(`event:ev-open-mic:${students[9].uid}`).set({ campusId: CAMPUS_ID, entityType: "event", entityId: "ev-open-mic", reason: "Venue in the description is wrong — it's moved to the Auditorium.", reporterUid: students[9].uid, status: "open", createdAt: ts(daysAgo(0.5)) });
  await db.collection(COL.events).doc("ev-open-mic").update({ reportCount: 1, reviewStatus: "flagged" });
  await db.collection(COL.supportRequests).add({ uid: students[14].uid, campusId: CAMPUS_ID, message: "My check-in at Valuation Masterclass didn't register even though I scanned.", status: "open", createdAt: ts(daysAgo(1)) });

  // Audit trail flavour --------------------------------------------------
  await db.collection(COL.auditLogs).add({ actorUid: admin.uid, action: "role.grant", entityType: "membership", entityId: ids.membership(CAMPUS_ID, organizer.uid), campusId: CAMPUS_ID, reason: "Finance Club president", before: { roles: ["student"] }, after: { roles: ["student", "organizer"], clubIds: ["finance-club"] }, at: ts(daysAgo(38)) });
  await db.collection(COL.auditLogs).add({ actorUid: admin.uid, action: "reward.create", entityType: "reward", entityId: "rw-canteen-50", campusId: CAMPUS_ID, before: null, after: { inventory: 120, coinCost: 100, status: "active" }, at: ts(daysAgo(30)) });

  // Daily metrics + leaderboard (computed from the data above).
  const { aggregateCampusDay, computeLeaderboard } = await import("../src/handlers/metrics");
  const { normalizeCampus } = await import("../src/lib/campus");
  const campusDoc = normalizeCampus(CAMPUS_ID, (await db.collection(COL.campuses).doc(CAMPUS_ID).get()).data()!);
  for (let i = 41; i >= 0; i--) await aggregateCampusDay(campusDoc, new Date(NOW.getTime() - i * 86400000));
  await computeLeaderboard(campusDoc, NOW);
  await db.collection(COL.notificationJobs).doc("seed-marker").set({ uid: "seed", campusId: CAMPUS_ID, category: "transactional", title: "seed", body: "seed", status: "cancelled", scheduledFor: ts(NOW), createdAt: ts(NOW), attempts: 0 });

  console.log("\nSeed complete. Emulator-only demo accounts (password: " + PASSWORD + "):");
  for (const p of named) console.log(`  ${p.roles.filter((r) => r !== "student").join("+") || "student"}`.padEnd(28) + p.email);
  console.log("\nAll users, events and reviews are synthetic. Never run this against a real project.");
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
