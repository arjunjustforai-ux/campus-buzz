import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/models/models.dart';

final liveQuestsProvider = StreamProvider<List<Quest>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null || !ref.watch(flagProvider(FeatureFlag.brandQuestsEnabled))) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.quests).where('campusIds', arrayContains: campusId).where('status', isEqualTo: 'live').where('endAt', isGreaterThanOrEqualTo: Timestamp.now()).snapshots().map((s) => s.docs.map(Quest.fromDoc).toList());
});

final questProvider = StreamProvider.family<Quest?, String>((ref, id) => ref.watch(firestoreProvider).collection(Col.quests).doc(id).snapshots().map((s) => s.exists ? Quest.fromDoc(s) : null));

final myQuestCompletionProvider = StreamProvider.family<QuestCompletion?, String>((ref, questId) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(firestoreProvider).collection(Col.questCompletions).doc(Ids.questCompletion(questId, uid)).snapshots().map((s) => s.exists ? QuestCompletion.fromDoc(s) : null);
});

final myQuestCompletionsProvider = StreamProvider<List<QuestCompletion>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.questCompletions).where('uid', isEqualTo: uid).snapshots().map((s) => s.docs.map(QuestCompletion.fromDoc).toList());
});
