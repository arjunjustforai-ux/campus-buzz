import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/models/models.dart';

final balanceProvider = StreamProvider<CoinBalance>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const CoinBalance());
  return ref.watch(firestoreProvider).collection(Col.coinBalances).doc(uid).snapshots().map((s) => s.exists ? CoinBalance.fromDoc(s) : const CoinBalance());
});

final participationStatsProvider = StreamProvider<ParticipationStats>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const ParticipationStats());
  return ref.watch(firestoreProvider).collection(Col.participationStats).doc(uid).snapshots().map((s) => s.exists ? ParticipationStats.fromDoc(s) : const ParticipationStats());
});

final ledgerProvider = StreamProvider<List<LedgerEntry>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.coinLedger).where('uid', isEqualTo: uid).orderBy('createdAt', descending: true).limit(100).snapshots().map((s) => s.docs.map(LedgerEntry.fromDoc).toList());
});
