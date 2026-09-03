import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/models/models.dart';

final rewardsProvider = StreamProvider<List<Reward>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.rewards).where('campusId', isEqualTo: campusId).where('status', isEqualTo: 'active').orderBy('coinCost').snapshots().map((s) => s.docs.map(Reward.fromDoc).toList());
});

final allRewardsProvider = StreamProvider<List<Reward>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.rewards).where('campusId', isEqualTo: campusId).snapshots().map((s) => (s.docs.map(Reward.fromDoc).toList())..sort((a, b) => a.coinCost.compareTo(b.coinCost)));
});

final rewardProvider = StreamProvider.family<Reward?, String>((ref, id) => ref.watch(firestoreProvider).collection(Col.rewards).doc(id).snapshots().map((s) => s.exists ? Reward.fromDoc(s) : null));

final myRedemptionsProvider = StreamProvider<List<Redemption>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.redemptions).where('uid', isEqualTo: uid).orderBy('issuedAt', descending: true).limit(50).snapshots().map((s) => s.docs.map(Redemption.fromDoc).toList());
});

final redemptionProvider = StreamProvider.family<Redemption?, String>((ref, id) => ref.watch(firestoreProvider).collection(Col.redemptions).doc(id).snapshots().map((s) => s.exists ? Redemption.fromDoc(s) : null));

final vendorsProvider = StreamProvider<List<Vendor>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.vendors).where('campusId', isEqualTo: campusId).snapshots().map((s) => s.docs.map(Vendor.fromDoc).toList());
});
