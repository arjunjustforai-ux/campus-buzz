import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../events/data/event_repository.dart';
import '../../events/presentation/event_card.dart';

final leaderboardProvider = StreamProvider<({String weekKey, List<LeaderboardRow> rows})?>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(null);
  return ref.watch(firestoreProvider).collection(Col.tribeLeaderboards).doc('${campusId}_current').snapshots().map((s) {
    if (!s.exists) return null;
    final rows = ((s.data()?['rows'] as List?) ?? const []).map((r) => LeaderboardRow.fromJson(Map<String, dynamic>.from(r as Map))).toList();
    return (weekKey: s.data()?['weekKey'] as String? ?? '', rows: rows);
  });
});

/// Weekly Tribe ranking by verified check-ins — never likes or views.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(flagProvider(FeatureFlag.tribeLeaderboardEnabled));
    final board = ref.watch(leaderboardProvider);
    final tribes = ref.watch(tribeMapProvider);
    final me = ref.watch(userProfileProvider).value;
    final t = Theme.of(context).textTheme;
    if (!on) return Scaffold(appBar: AppBar(title: const Text('Tribe leaderboard')), body: const CbEmpty(icon: Icons.emoji_events_outlined, title: 'Leaderboard coming soon'));
    return Scaffold(
      appBar: AppBar(title: const Text('Tribe leaderboard')),
      body: board.when(
        loading: () => const CbLoading(),
        error: (e, _) => CbErrorView(error: e),
        data: (b) {
          if (b == null || b.rows.isEmpty) return const CbEmpty(icon: Icons.emoji_events_outlined, title: 'No check-ins this week yet', message: 'The first Tribe to show up takes the lead.');
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('Week ${b.weekKey.split('-W').last} · verified check-ins', style: t.bodyMedium),
            const SizedBox(height: 12),
            for (final r in b.rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: CbCard(
                  borderColor: me?.tribeIds.contains(r.tribeId) == true ? CbColors.lime : null,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  onTap: () => context.push('/tribes/${r.tribeId}'),
                  child: Row(children: [
                    SizedBox(width: 36, child: Text('#${r.rank}', style: t.headlineSmall?.copyWith(color: r.rank == 1 ? CbColors.lime : r.rank <= 3 ? CbColors.orangeText : CbColors.textTertiary))),
                    Text(tribes[r.tribeId]?.emoji ?? '', style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(r.name, style: t.titleMedium)),
                    if (r.movement != null && r.movement != 0) Padding(padding: const EdgeInsets.only(right: 8), child: Row(children: [Icon(r.movement! > 0 ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: r.movement! > 0 ? CbColors.success : CbColors.danger), Text('${r.movement!.abs()}', style: t.labelSmall)])),
                    if (r.movement == 0) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.remove, size: 14, color: CbColors.textTertiary)),
                    Text('${r.count}', style: t.headlineSmall),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            Text('Ranks refresh every 30 minutes from real check-ins. Movement compares with last week.', style: t.bodySmall),
          ]);
        },
      ),
    );
  }
}

class TribeScreen extends ConsumerWidget {
  const TribeScreen({super.key, required this.tribeId});
  final String tribeId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tribe = ref.watch(tribeMapProvider)[tribeId];
    final events = ref.watch(upcomingEventsProvider);
    final me = ref.watch(userProfileProvider).value;
    final t = Theme.of(context).textTheme;
    final isMine = me?.tribeIds.contains(tribeId) == true;
    return Scaffold(
      appBar: AppBar(title: Text('${tribe?.emoji ?? ''} ${tribe?.name ?? 'Tribe'}'.trim())),
      body: events.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) {
          final mine = list.where((e) => e.tribeIds.contains(tribeId)).toList();
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (tribe != null && tribe.description.isNotEmpty) Text(tribe.description, style: t.bodyLarge?.copyWith(color: CbColors.textSecondary)),
            const SizedBox(height: 8),
            Row(children: [
              if (isMine) const CbStatusPill(label: 'Your Tribe', color: CbColors.lime, icon: Icons.star)
              else OutlinedButton.icon(onPressed: me == null ? null : () async { try { await ref.read(firestoreProvider).collection(Col.users).doc(me.uid).update({'tribeIds': FieldValue.arrayUnion([tribeId])}); if (context.mounted) showCbSnack(context, 'Added to your Tribes.'); } catch (e) { if (context.mounted) showCbError(context, e); } }, icon: const Icon(Icons.add, size: 16), label: const Text('Join Tribe')),
            ]),
            const SizedBox(height: 16),
            Text('Upcoming for this Tribe', style: t.titleLarge),
            const SizedBox(height: 10),
            if (mine.isEmpty) const CbEmpty(icon: Icons.event_busy, title: 'Nothing yet', message: 'Organizers tag events with Tribes when they post.'),
            for (final e in mine) Padding(padding: const EdgeInsets.only(bottom: 12), child: EventCard(event: e, source: 'tribe_filter')),
          ]);
        },
      ),
    );
  }
}
