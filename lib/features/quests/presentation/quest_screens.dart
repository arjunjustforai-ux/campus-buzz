import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/models/models.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../events/data/event_repository.dart';
import '../data/quest_repository.dart';

class QuestsScreen extends ConsumerWidget {
  const QuestsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(liveQuestsProvider);
    final mine = {for (final c in ref.watch(myQuestCompletionsProvider).value ?? const <QuestCompletion>[]) c.questId: c};
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sponsored quests')),
      body: quests.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) => list.isEmpty
            ? const CbEmpty(icon: Icons.workspace_premium_outlined, title: 'No quests right now', message: 'Brands sponsor participation challenges here. Verified check-ins only.')
            : ListView.separated(padding: const EdgeInsets.all(16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (_, i) {
                final q = list[i]; final c = mine[q.id];
                return CbCard(onTap: () => context.push('/quests/${q.id}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [CbStatusPill(label: q.sponsorDisclosure, color: CbColors.orangeText, icon: Icons.campaign), const Spacer(), CbCoinBadge(amount: q.rewardCoins)]),
                  const SizedBox(height: 10),
                  Text(q.title, style: t.titleLarge),
                  Text(q.typeLabel, style: t.bodySmall),
                  const SizedBox(height: 8),
                  Text(q.description, style: t.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 10),
                  Row(children: [Text('Ends ${Fmt.date(q.endAt, ref.watch(campusTimezoneProvider))}', style: t.labelSmall), const Spacer(), if (c != null) CbStatusPill(label: c.status == 'completed' ? 'Completed' : 'Joined', color: c.status == 'completed' ? CbColors.success : CbColors.lime, icon: c.status == 'completed' ? Icons.check : Icons.play_arrow)]),
                ]));
              }),
      ),
    );
  }
}

class QuestDetailScreen extends ConsumerStatefulWidget {
  const QuestDetailScreen({super.key, required this.questId});
  final String questId;
  @override
  ConsumerState<QuestDetailScreen> createState() => _QuestDetailScreenState();
}

class _QuestDetailScreenState extends ConsumerState<QuestDetailScreen> {
  bool _busy = false; final Set<String> _checked = {};
  bool _tracked = false;

  Future<void> _join() async {
    setState(() => _busy = true);
    try { await ref.read(functionsProvider).call('joinQuest', {'questId': widget.questId}); if (mounted) showCbSnack(context, "You're in. Show up and it completes automatically."); } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _submitChecklist() async {
    setState(() => _busy = true);
    try { final r = await ref.read(functionsProvider).call('submitQuestChecklist', {'questId': widget.questId, 'items': _checked.toList()}); if (mounted) showCbSnack(context, '${r['done']}/${r['required']} done.'); } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final quest = ref.watch(questProvider(widget.questId));
    final completion = ref.watch(myQuestCompletionProvider(widget.questId)).value;
    final tribes = ref.watch(tribeMapProvider);
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    if (!_tracked) { _tracked = true; WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(analyticsProvider).track('quest_viewed', {'questId': widget.questId})); }
    return Scaffold(
      appBar: AppBar(title: const Text('Quest')),
      body: quest.when(
        loading: () => const CbLoading(),
        error: (e, _) => CbErrorView(error: e),
        data: (q) {
          if (q == null) return const CbEmpty(title: 'Quest not found');
          final checklist = (q.criteria['checklist'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
          final progressList = (completion?.progress['checklist'] as List?)?.map((e) => e.toString()).toSet() ?? const <String>{};
          if (_checked.isEmpty && progressList.isNotEmpty) _checked.addAll(progressList);
          final count = (q.criteria['count'] as num?)?.toInt() ?? 0;
          final done = (completion?.progress['count'] as num?)?.toInt() ?? 0;
          return ListView(padding: const EdgeInsets.all(16), children: [
            CbStatusPill(label: q.sponsorDisclosure, color: CbColors.orangeText, icon: Icons.campaign),
            const SizedBox(height: 10),
            Text(q.title, style: t.headlineMedium),
            const SizedBox(height: 6),
            Row(children: [CbCoinBadge(amount: q.rewardCoins, large: true), const SizedBox(width: 10), Text('${Fmt.date(q.startAt, tz)} → ${Fmt.date(q.endAt, tz)}', style: t.bodySmall)]),
            const SizedBox(height: 16),
            Text(q.description, style: t.bodyLarge?.copyWith(color: CbColors.textSecondary, height: 1.5)),
            const SizedBox(height: 16),
            CbCard(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('How to complete', style: t.titleMedium),
              const SizedBox(height: 4),
              Text(switch (q.type) { 'event_attendance' => 'Check in (QR) at a qualifying event.', 'qr_activation' => 'Scan the check-in QR at the sponsored event.', 'event_count' => 'Verified check-ins at $count events${(q.criteria['tagFilter'] as List?)?.isNotEmpty == true ? ' tagged ${(q.criteria['tagFilter'] as List).join(', ')}' : ''}.', 'checklist' => 'Tick every item below.', 'streak' => 'Keep a ${q.criteria['streakWeeks'] ?? 3}-week participation streak.', _ => q.typeLabel }, style: t.bodyMedium),
              if (q.tribeIds.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, children: [for (final id in q.tribeIds) CbChip(label: tribes[id]?.name ?? id, small: true)])),
            ])),
            const SizedBox(height: 16),
            if (completion == null) FilledButton(onPressed: _busy ? null : _join, child: const Text('Join quest'))
            else if (completion.status == 'completed') CbCard(gradient: true, child: Row(children: [const Icon(Icons.verified, color: CbColors.limeText), const SizedBox(width: 10), Expanded(child: Text('Completed · +${completion.coinsAwarded} BuzzCoins', style: t.titleMedium))]))
            else ...[
              if (q.type == 'event_count') Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('$done of $count events', style: t.titleMedium), const SizedBox(height: 6), LinearProgressIndicator(value: count == 0 ? 0 : done / count, minHeight: 8, borderRadius: BorderRadius.circular(4))]),
              if (q.type == 'checklist') ...[
                for (final item in checklist) CheckboxListTile(value: _checked.contains(item), onChanged: (v) => setState(() => v == true ? _checked.add(item) : _checked.remove(item)), title: Text(item), controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero),
                FilledButton(onPressed: _busy ? null : _submitChecklist, child: const Text('Save progress')),
              ],
              if (q.type != 'checklist' && q.type != 'event_count') Text('Joined. Your next qualifying check-in completes it.', style: t.bodyMedium?.copyWith(color: CbColors.limeText)),
            ],
            if (q.terms.isNotEmpty) ...[const SizedBox(height: 20), Text('Terms', style: t.titleSmall), Text(q.terms, style: t.bodySmall)],
            const SizedBox(height: 8),
            Text('The sponsor only sees aggregate numbers — never your name.', style: t.bodySmall),
          ]);
        },
      ),
    );
  }
}
