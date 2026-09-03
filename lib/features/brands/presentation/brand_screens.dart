import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/models/models.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/charts.dart';
import '../../../core/widgets/state_views.dart';

final brandQuestsProvider = StreamProvider.family<List<Quest>, String>((ref, brandId) => ref.watch(firestoreProvider).collection(Col.quests).where('brandId', isEqualTo: brandId).orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map(Quest.fromDoc).toList()));
final brandAccountProvider = StreamProvider.family<BrandAccount?, String>((ref, id) => ref.watch(firestoreProvider).collection(Col.brandAccounts).doc(id).snapshots().map((s) => s.exists ? BrandAccount.fromDoc(s) : null));
final activeCampusesProvider = StreamProvider<List<Campus>>((ref) => ref.watch(firestoreProvider).collection(Col.campuses).where('status', isEqualTo: 'active').snapshots().map((s) => s.docs.map(Campus.fromDoc).toList()));
final tribesForCampusesProvider = StreamProvider.family<List<Tribe>, List<String>>((ref, ids) => ids.isEmpty ? Stream.value(const []) : ref.watch(firestoreProvider).collection(Col.tribes).where('campusId', whereIn: ids.take(10).toList()).snapshots().map((s) => s.docs.map(Tribe.fromDoc).toList()));

class _BrandCtx extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}
final selectedBrandProvider = NotifierProvider<_BrandCtx, String?>(_BrandCtx.new);

String? _brandId(WidgetRef ref) {
  final brands = ref.watch(brandMembershipsProvider).value ?? const [];
  final sel = ref.watch(selectedBrandProvider);
  return sel ?? brands.firstOrNull;
}

Color _statusColor(String s) => switch (s) { 'live' => CbColors.success, 'approved' => CbColors.lime, 'submitted' => CbColors.warning, 'paused' => CbColors.info, 'completed' => CbColors.textTertiary, 'cancelled' => CbColors.danger, _ => CbColors.textSecondary };

class BrandDashboardScreen extends ConsumerWidget {
  const BrandDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandId = _brandId(ref);
    final brands = ref.watch(brandMembershipsProvider).value ?? const [];
    if (brandId == null) return const CbEmpty(icon: Icons.storefront_outlined, title: 'No brand account linked', message: 'CampusBuzz links your login to a brand account before you can run quests.');
    final quests = ref.watch(brandQuestsProvider(brandId));
    final brand = ref.watch(brandAccountProvider(brandId)).value;
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: brand?.name ?? 'Brand',
      subtitle: 'Quests are participation campaigns, verified by QR check-ins. Never banner ads.',
      actions: [if (brands.length > 1) DropdownButton<String>(value: brandId, items: [for (final b in brands) DropdownMenuItem(value: b, child: Text(b))], onChanged: (v) => ref.read(selectedBrandProvider.notifier).set(v)), FilledButton.icon(onPressed: () => context.go('/brand/quests/new'), icon: const Icon(Icons.add), label: const Text('New quest'))],
      child: quests.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) {
          final live = list.where((q) => q.status == 'live').length;
          final completions = list.fold<int>(0, (s, q) => s + ((q.stats['completions'] as num?)?.toInt() ?? 0));
          final joins = list.fold<int>(0, (s, q) => s + ((q.stats['joins'] as num?)?.toInt() ?? 0));
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CbStatGrid(children: [CbStat(label: 'Live quests', value: '$live', icon: Icons.play_circle_outline), CbStat(label: 'Joins', value: '$joins', icon: Icons.group_add_outlined), CbStat(label: 'Verified completions', value: '$completions', icon: Icons.verified), CbStat(label: 'Completion rate', value: Fmt.pct(joins == 0 ? null : completions / joins * 100), icon: Icons.trending_up)]),
            const SizedBox(height: 20),
            Text('Quests', style: t.titleLarge),
            const SizedBox(height: 8),
            if (list.isEmpty) const CbEmpty(icon: Icons.workspace_premium_outlined, title: 'No quests yet', message: 'Draft one, submit it, and CampusBuzz approves it before students see it.'),
            for (final q in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: CbCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), onTap: () => context.go('/brand/quests/${q.id}'), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(q.title, style: t.titleSmall), Text('${q.typeLabel} · ${q.campusIds.length} campus${q.campusIds.length == 1 ? '' : 'es'} · ${q.stats['joins'] ?? 0} joins · ${q.stats['completions'] ?? 0} completions', style: t.bodySmall)])), CbStatusPill(label: q.status, color: _statusColor(q.status))]))),
          ]);
        },
      ),
    );
  }
}

class QuestFormScreen extends ConsumerStatefulWidget {
  const QuestFormScreen({super.key, this.questId});
  final String? questId;
  @override
  ConsumerState<QuestFormScreen> createState() => _QuestFormScreenState();
}

class _QuestFormScreenState extends ConsumerState<QuestFormScreen> {
  final _title = TextEditingController(), _desc = TextEditingController(), _reward = TextEditingController(text: '25'), _limit = TextEditingController(text: '500'), _value = TextEditingController(), _terms = TextEditingController(), _disclosure = TextEditingController(text: 'Sponsored quest'), _count = TextEditingController(text: '2'), _tagFilter = TextEditingController(), _checklist = TextEditingController(), _eventIds = TextEditingController(), _streak = TextEditingController(text: '3');
  String _type = 'event_attendance'; DateTime? _start; DateTime? _end; final Set<String> _campuses = {}; final Set<String> _tribes = {}; bool _busy = false, _loaded = false;

  void _load(Quest q) {
    if (_loaded) return; _loaded = true;
    _title.text = q.title; _desc.text = q.description; _reward.text = '${q.rewardCoins}'; _limit.text = '${q.participantLimit}'; _value.text = q.campaignValue == 0 ? '' : '${q.campaignValue}'; _terms.text = q.terms; _disclosure.text = q.sponsorDisclosure; _type = q.type; _start = q.startAt.toLocal(); _end = q.endAt.toLocal(); _campuses.addAll(q.campusIds); _tribes.addAll(q.tribeIds);
    _count.text = '${q.criteria['count'] ?? 2}'; _tagFilter.text = ((q.criteria['tagFilter'] as List?) ?? const []).join(', '); _checklist.text = ((q.criteria['checklist'] as List?) ?? const []).join('\n'); _eventIds.text = ((q.criteria['eventIds'] as List?) ?? const []).join(', '); _streak.text = '${q.criteria['streakWeeks'] ?? 3}';
  }

  Future<void> _pick(bool start) async {
    final d = await showDatePicker(context: context, initialDate: (start ? _start : _end) ?? DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null) setState(() => start ? _start = d : _end = DateTime(d.year, d.month, d.day, 23, 59));
  }

  Future<void> _save({bool submit = false}) async {
    final brandId = _brandId(ref);
    if (brandId == null || _start == null || _end == null || _campuses.isEmpty) { showCbSnack(context, 'Add dates and at least one campus.', error: true); return; }
    setState(() => _busy = true);
    try {
      final r = await ref.read(functionsProvider).call('saveQuestDraft', {
        'brandId': brandId, 'questId': widget.questId, 'title': _title.text.trim(), 'description': _desc.text.trim(), 'type': _type, 'campusIds': _campuses.toList(), 'tribeIds': _tribes.toList(), 'startAt': _start!.toUtc().toIso8601String(), 'endAt': _end!.toUtc().toIso8601String(),
        'criteria': {'eventIds': _eventIds.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(), 'count': int.tryParse(_count.text) ?? 1, 'checklist': _checklist.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(), 'streakWeeks': int.tryParse(_streak.text) ?? 3, 'tagFilter': _tagFilter.text.split(',').map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList()},
        'rewardCoins': int.tryParse(_reward.text) ?? 0, 'participantLimit': int.tryParse(_limit.text) ?? 0, 'campaignValue': double.tryParse(_value.text) ?? 0, 'terms': _terms.text.trim(), 'sponsorDisclosure': _disclosure.text.trim(),
      });
      final id = r['questId'] as String;
      if (submit) { await ref.read(functionsProvider).call('submitBrandQuest', {'questId': id}); }
      if (mounted) { showCbSnack(context, submit ? 'Submitted for CampusBuzz approval.' : 'Draft saved.'); context.go('/brand/quests/$id'); }
    } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.questId == null ? null : ref.watch(_questProvider(widget.questId!)).value;
    if (existing != null) _load(existing);
    final campuses = ref.watch(activeCampusesProvider).value ?? const <Campus>[];
    final tribes = ref.watch(tribesForCampusesProvider(_campuses.toList())).value ?? const <Tribe>[];
    final tz = 'Asia/Kolkata';
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: widget.questId == null ? 'New quest' : 'Edit quest',
      subtitle: 'Only verifiable objectives: attendance, QR activation, event counts, checklists, streaks.',
      maxWidth: 760,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _title, maxLength: 100, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: _desc, maxLines: 4, maxLength: 2000, decoration: const InputDecoration(labelText: 'Description (students see this)')),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: _type, decoration: const InputDecoration(labelText: 'Quest type'), items: const [DropdownMenuItem(value: 'event_attendance', child: Text('Attend an event')), DropdownMenuItem(value: 'qr_activation', child: Text('QR activation at a sponsored event')), DropdownMenuItem(value: 'event_count', child: Text('Number-of-events challenge')), DropdownMenuItem(value: 'checklist', child: Text('Structured checklist')), DropdownMenuItem(value: 'streak', child: Text('Streak-based participation'))], onChanged: (v) => setState(() => _type = v!)),
        const SizedBox(height: 8),
        if (_type == 'event_attendance' || _type == 'qr_activation') TextField(controller: _eventIds, decoration: const InputDecoration(labelText: 'Event IDs (comma separated; empty = any event)')),
        if (_type == 'event_count') Row(children: [Expanded(child: TextField(controller: _count, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Events required'))), const SizedBox(width: 8), Expanded(child: TextField(controller: _tagFilter, decoration: const InputDecoration(labelText: 'Tag filter (e.g. sports)')))]),
        if (_type == 'checklist') TextField(controller: _checklist, maxLines: 4, decoration: const InputDecoration(labelText: 'Checklist items (one per line)')),
        if (_type == 'streak') TextField(controller: _streak, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Streak weeks required')),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.calendar_today, size: 18), label: Text(_start == null ? 'Start' : Fmt.date(_start!.toUtc(), tz)))), const SizedBox(width: 8), Expanded(child: OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.event, size: 18), label: Text(_end == null ? 'End' : Fmt.date(_end!.toUtc(), tz))))]),
        const SizedBox(height: 12),
        Text('Eligible campuses', style: t.titleSmall),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final c in campuses) CbChip(label: c.shortName, selected: _campuses.contains(c.id), onTap: () => setState(() => _campuses.contains(c.id) ? _campuses.remove(c.id) : _campuses.add(c.id)))]),
        const SizedBox(height: 12),
        Text('Target Tribes (optional)', style: t.titleSmall),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final tr in tribes) CbChip(label: '${tr.emoji} ${tr.name}', selected: _tribes.contains(tr.id), onTap: () => setState(() => _tribes.contains(tr.id) ? _tribes.remove(tr.id) : _tribes.add(tr.id)))]),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: TextField(controller: _reward, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Reward (BuzzCoins)'))), const SizedBox(width: 8), Expanded(child: TextField(controller: _limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Participant limit (0 = none)'))), const SizedBox(width: 8), Expanded(child: TextField(controller: _value, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Campaign value ₹ (for CPA)')))]),
        const SizedBox(height: 8),
        TextField(controller: _disclosure, decoration: const InputDecoration(labelText: 'Sponsor disclosure label')),
        TextField(controller: _terms, maxLines: 3, decoration: const InputDecoration(labelText: 'Terms')),
        const SizedBox(height: 20),
        Row(children: [Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _save(), child: const Text('Save draft'))), const SizedBox(width: 12), Expanded(child: FilledButton(onPressed: _busy ? null : () => _save(submit: true), child: const Text('Submit for approval')))]),
      ]),
    );
  }
}

final _questProvider = StreamProvider.family<Quest?, String>((ref, id) => ref.watch(firestoreProvider).collection(Col.quests).doc(id).snapshots().map((s) => s.exists ? Quest.fromDoc(s) : null));
final _analyticsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) => ref.read(functionsProvider).call('getBrandQuestAnalytics', {'questId': id}));

class BrandQuestScreen extends ConsumerWidget {
  const BrandQuestScreen({super.key, required this.questId});
  final String questId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quest = ref.watch(_questProvider(questId));
    final analytics = ref.watch(_analyticsProvider(questId));
    final t = Theme.of(context).textTheme;
    Future<void> status(String s) async { try { await ref.read(functionsProvider).call('updateQuestStatus', {'questId': questId, 'status': s}); if (context.mounted) showCbSnack(context, 'Quest $s.'); } catch (e) { if (context.mounted) showCbError(context, e); } }
    return quest.when(
      loading: () => const CbLoading(),
      error: (e, _) => CbErrorView(error: e),
      data: (q) {
        if (q == null) return const CbEmpty(title: 'Quest not found');
        return CbPage(
          title: q.title,
          subtitle: '${q.typeLabel} · ${Fmt.date(q.startAt, 'Asia/Kolkata')} → ${Fmt.date(q.endAt, 'Asia/Kolkata')}',
          actions: [
            CbStatusPill(label: q.status, color: _statusColor(q.status)),
            CbStatusPill(label: 'Finance: ${q.financialStatus}', color: CbColors.textSecondary, icon: Icons.account_balance_wallet_outlined),
            if (q.status == 'draft') OutlinedButton(onPressed: () => context.go('/brand/quests/$questId/edit'), child: const Text('Edit')),
            if (q.status == 'draft') FilledButton(onPressed: () async { try { await ref.read(functionsProvider).call('submitBrandQuest', {'questId': questId}); if (context.mounted) showCbSnack(context, 'Submitted for approval.'); } catch (e) { if (context.mounted) showCbError(context, e); } }, child: const Text('Submit')),
            if (q.status == 'live') OutlinedButton(onPressed: () => status('paused'), child: const Text('Pause')),
            if (q.status == 'paused' || q.status == 'approved') FilledButton(onPressed: () => status('live'), child: const Text('Go live')),
            if (q.status == 'live' || q.status == 'paused') OutlinedButton(onPressed: () async { if (await confirm(context, title: 'Complete this quest?')) status('completed'); }, child: const Text('Complete')),
            OutlinedButton.icon(onPressed: () => ref.invalidate(_analyticsProvider(questId)), icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (q.rejectionReason != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: CbCard(borderColor: CbColors.danger, padding: const EdgeInsets.all(12), child: Text('Returned by CampusBuzz: ${q.rejectionReason}'))),
            Text(q.description, style: t.bodyLarge?.copyWith(color: CbColors.textSecondary)),
            const SizedBox(height: 16),
            analytics.when(
              loading: () => const CbLoading(message: 'Loading aggregate performance…'),
              error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(_analyticsProvider(questId))),
              data: (a) {
                final timeline = Map<String, dynamic>.from(a['timeline'] as Map? ?? {});
                final days = timeline.keys.toList()..sort();
                final tribe = Map<String, dynamic>.from(a['tribeBreakdown'] as Map? ?? {});
                final campus = Map<String, dynamic>.from(a['campusBreakdown'] as Map? ?? {});
                return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CbStatGrid(children: [
                    CbStat(label: 'Eligible audience', value: '${a['eligibleAudience']}', icon: Icons.groups_outlined),
                    CbStat(label: 'Views', value: '${a['views']}', icon: Icons.visibility_outlined),
                    CbStat(label: 'Joins', value: '${a['joins']}', icon: Icons.group_add_outlined),
                    CbStat(label: 'Verified completions', value: '${a['completions']}', icon: Icons.verified, color: CbColors.limeText),
                    CbStat(label: 'Completion rate', value: Fmt.pct(a['completionRate'] as num?), icon: Icons.trending_up),
                    CbStat(label: 'Repeat participation', value: '${a['repeatParticipation']}', hint: 'Completed another of your quests', icon: Icons.repeat),
                    CbStat(label: 'Coins distributed', value: '${a['coinsDistributed']}', icon: Icons.hexagon_rounded),
                    CbStat(label: 'Cost per verified action', value: a['costPerVerifiedAction'] == null ? '—' : Fmt.rupees(a['costPerVerifiedAction'] as num), hint: a['costPerVerifiedAction'] == null ? 'Enter campaign value to compute' : 'campaign value ÷ completions', icon: Icons.calculate_outlined),
                  ]),
                  const SizedBox(height: 16),
                  CbLineChart(title: 'Completions timeline', period: 'per day', points: days.map((d) => (timeline[d] as num).toDouble()).toList(), labels: days.map((d) => d.substring(5)).toList()),
                  const SizedBox(height: 12),
                  LayoutBuilder(builder: (context, c) {
                    final charts = [
                      CbBarChart(title: 'Tribe breakdown (completions)', period: 'groups under ${a['minGroupSize']} hidden', values: tribe.values.map((v) => ((v as num?) ?? 0).toDouble()).toList(), labels: tribe.keys.toList(), color: CbColors.lime),
                      CbBarChart(title: 'Campus breakdown', period: 'joins vs completions', values: campus.values.map((v) => (((v as Map)['joins'] as num?) ?? 0).toDouble()).toList(), secondary: campus.values.map((v) => (((v as Map)['completions'] as num?) ?? 0).toDouble()).toList(), labels: campus.keys.toList(), primaryLabel: 'Joins', secondaryLabel: 'Completions'),
                    ];
                    return c.maxWidth > 900 ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final ch in charts) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: ch))]) : Column(children: [for (final ch in charts) Padding(padding: const EdgeInsets.only(bottom: 12), child: ch)]);
                  }),
                  const SizedBox(height: 12),
                  Text('All figures are aggregates of verified participation. Groups smaller than ${a['minGroupSize']} students are suppressed; individual identities are never shared.', style: t.bodySmall),
                ]);
              },
            ),
          ]),
        );
      },
    );
  }
}

Timestamp nowTs() => Timestamp.now();
