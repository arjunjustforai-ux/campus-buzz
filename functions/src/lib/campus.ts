import { COL } from "../config/collections";
import { DEFAULT_ECONOMY, DEFAULT_FEATURE_FLAGS, DEFAULT_PILOT } from "../config/defaults";
import { fail } from "../domain/errors";
import type { EconomyConfig, FeatureFlags, PilotConfig } from "../domain/types";
import { db } from "./firestore";

export interface CampusDoc {
  id: string;
  name: string;
  shortName: string;
  domains: string[];
  timezone: string;
  status: "active" | "inactive";
  economy: EconomyConfig;
  pilot: PilotConfig;
  featureFlags: FeatureFlags;
  privacyPolicyUrl?: string;
  termsUrl?: string;
}

export async function loadCampus(campusId: string, tx?: FirebaseFirestore.Transaction): Promise<CampusDoc> {
  const ref = db.collection(COL.campuses).doc(campusId);
  const snap = tx ? await tx.get(ref) : await ref.get();
  if (!snap.exists) fail("not_found", "Campus not found");
  return normalizeCampus(snap.id, snap.data()!);
}

export function normalizeCampus(id: string, d: FirebaseFirestore.DocumentData): CampusDoc {
  return {
    id,
    name: d.name ?? id,
    shortName: d.shortName ?? d.name ?? id,
    domains: Array.isArray(d.domains) ? d.domains : [],
    timezone: d.timezone ?? "Asia/Kolkata",
    status: d.status ?? "active",
    economy: { ...DEFAULT_ECONOMY, ...(d.economy ?? {}) },
    pilot: {
      targets: { ...DEFAULT_PILOT.targets, ...(d.pilot?.targets ?? {}) },
      bands: { ...DEFAULT_PILOT.bands, ...(d.pilot?.bands ?? {}) },
      economyHealth: { ...DEFAULT_PILOT.economyHealth, ...(d.pilot?.economyHealth ?? {}) },
    },
    featureFlags: { ...DEFAULT_FEATURE_FLAGS, ...(d.featureFlags ?? {}) },
    privacyPolicyUrl: d.privacyPolicyUrl,
    termsUrl: d.termsUrl,
  };
}

/** Effective flags = campus overrides on top of defaults (Remote Config is a client-side concern). */
export async function featureFlags(campusId: string): Promise<FeatureFlags> {
  const [campusSnap, cfgSnap] = await Promise.all([
    db.collection(COL.campuses).doc(campusId).get(),
    db.collection(COL.featureConfigs).doc(campusId).get(),
  ]);
  return {
    ...DEFAULT_FEATURE_FLAGS,
    ...(campusSnap.data()?.featureFlags ?? {}),
    ...(cfgSnap.data()?.flags ?? {}),
  };
}

export async function requireFlag(campusId: string, flag: keyof FeatureFlags): Promise<void> {
  const flags = await featureFlags(campusId);
  if (!flags[flag]) fail("feature_disabled", `${flag} is not enabled on this campus`);
}

/** Resolve a campus from an email's domain using the admin-controlled allowlist. */
export async function resolveCampusByEmail(email: string): Promise<CampusDoc | null> {
  const domain = email.toLowerCase().split("@")[1];
  if (!domain) return null;
  const snap = await db
    .collection(COL.campuses)
    .where("domains", "array-contains", domain)
    .where("status", "==", "active")
    .limit(1)
    .get();
  if (snap.empty) return null;
  return normalizeCampus(snap.docs[0].id, snap.docs[0].data());
}
