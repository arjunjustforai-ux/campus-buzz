import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/collections.dart';
import '../constants/feature_flags.dart';
import '../models/models.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

/// Firebase auth state (null when signed out).
final authStateProvider = StreamProvider<User?>((ref) => ref.watch(firebaseAuthProvider).userChanges());

final currentUidProvider = Provider<String?>((ref) => ref.watch(authStateProvider).value?.uid);

/// Live `users/{uid}` profile. Null until onboarding creates it.
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreProvider).collection(Col.users).doc(uid).snapshots().map((s) => s.exists ? UserProfile.fromDoc(s) : null);
});

final activeCampusIdProvider = Provider<String?>((ref) => ref.watch(userProfileProvider).value?.activeCampusId);

final campusProvider = StreamProvider<Campus?>((ref) {
  final id = ref.watch(activeCampusIdProvider);
  if (id == null) return Stream.value(null);
  return ref.watch(firestoreProvider).collection(Col.campuses).doc(id).snapshots().map((s) => s.exists ? Campus.fromDoc(s) : null);
});

final campusByIdProvider = StreamProvider.family<Campus?, String>((ref, id) =>
    ref.watch(firestoreProvider).collection(Col.campuses).doc(id).snapshots().map((s) => s.exists ? Campus.fromDoc(s) : null));

/// Campus timezone with a safe default until the campus loads.
final campusTimezoneProvider = Provider<String>((ref) => ref.watch(campusProvider).value?.timezone ?? 'Asia/Kolkata');
final economyProvider = Provider<EconomyConfig>((ref) => ref.watch(campusProvider).value?.economy ?? const EconomyConfig());

/// Membership for the active campus — the ONLY source of truth for roles on the client
/// (and it is never client-writable; see firestore.rules).
final membershipProvider = StreamProvider<Membership?>((ref) {
  final uid = ref.watch(currentUidProvider);
  final campusId = ref.watch(activeCampusIdProvider);
  if (uid == null || campusId == null) return Stream.value(null);
  return ref.watch(firestoreProvider).collection(Col.memberships).doc(Ids.membership(campusId, uid)).snapshots().map((s) => s.exists ? Membership.fromDoc(s) : null);
});

/// All memberships across campuses (for the campus switcher).
final allMembershipsProvider = StreamProvider<List<Membership>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.memberships).where('uid', isEqualTo: uid).snapshots().map((s) => s.docs.map(Membership.fromDoc).toList());
});

final rolesProvider = Provider<Set<Role>>((ref) {
  final m = ref.watch(membershipProvider).value;
  final profile = ref.watch(userProfileProvider).value;
  final roles = {...?m?.roles};
  if (profile?.superAdmin == true) roles.addAll({Role.superAdmin, Role.campusAdmin});
  return roles;
});

final hasRoleProvider = Provider.family<bool, Role>((ref, role) => ref.watch(rolesProvider).contains(role));
final isSuperAdminProvider = Provider<bool>((ref) => ref.watch(userProfileProvider).value?.superAdmin == true);

/// Brand memberships (brand users may not be campus members of every campus).
final brandMembershipsProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.brandMemberships).where('uid', isEqualTo: uid).where('status', isEqualTo: 'active').snapshots().map((s) => s.docs.map((d) => d.get('brandId') as String).toList());
});

/// Effective feature flags: defaults ← campus doc ← feature_configs overrides ← Remote Config (set by RemoteConfigService).
class RemoteFlagOverrides extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => const {};
  void set(Map<String, bool> v) => state = v;
}

final remoteFlagOverridesProvider = NotifierProvider<RemoteFlagOverrides, Map<String, bool>>(RemoteFlagOverrides.new);

final featureConfigOverridesProvider = StreamProvider<Map<String, bool>>((ref) {
  final id = ref.watch(activeCampusIdProvider);
  if (id == null) return Stream.value(const {});
  return ref.watch(firestoreProvider).collection(Col.featureConfigs).doc(id).snapshots().map((s) => ((s.data()?['flags'] as Map?) ?? const {}).map((k, v) => MapEntry(k.toString(), v == true)));
});

final featureFlagsProvider = Provider<Map<String, bool>>((ref) {
  final campus = ref.watch(campusProvider).value?.featureFlags ?? const {};
  final cfg = ref.watch(featureConfigOverridesProvider).value ?? const {};
  final remote = ref.watch(remoteFlagOverridesProvider);
  return {for (final f in FeatureFlag.values) f.key: cfg[f.key] ?? campus[f.key] ?? remote[f.key] ?? f.defaultValue};
});

final flagProvider = Provider.family<bool, FeatureFlag>((ref, flag) => ref.watch(featureFlagsProvider)[flag.key] ?? flag.defaultValue);

/// Where the router should send the user.
enum AuthPhase { loading, signedOut, unverified, needsOnboarding, suspended, ready }

final authPhaseProvider = Provider<AuthPhase>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth.isLoading) return AuthPhase.loading;
  final user = auth.value;
  if (user == null) return AuthPhase.signedOut;
  if (!user.emailVerified) return AuthPhase.unverified;
  final profile = ref.watch(userProfileProvider);
  if (profile.isLoading) return AuthPhase.loading;
  final p = profile.value;
  if (p == null || !p.onboardingCompleted) return AuthPhase.needsOnboarding;
  if (p.isSuspended) return AuthPhase.suspended;
  return AuthPhase.ready;
});
