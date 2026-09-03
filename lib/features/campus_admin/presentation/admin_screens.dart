import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/models/models.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/charts.dart';
import '../../../core/widgets/state_views.dart';
import '../../events/data/event_repository.dart';
import '../../rewards/data/reward_repository.dart';

/* ------------------------------------------------------------------ */
/* Providers                                                           */
/* ------------------------------------------------------------------ */

final campusDashboardProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) throw StateError('no campus');
  return ref.read(functionsProvider).call('getCampusDashboard', {'campusId': campusId});
});

final pilotHistoryProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.pilotMetrics).where('campusId', isEqualTo: campusId).orderBy('weekKey', descending: true).limit(12).snapshots().map((s) => s.docs.map((d) => d.data()).toList());
});

final reviewQueueProvider = StreamProvider<List<Event>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.events).where('campusId', isEqualTo: campusId).where('reviewStatus', whereIn: ['pending_review', 'flagged']).orderBy('publishedAt', descending: true).limit(100).snapshots().map((s) => s.docs.map(Event.fromDoc).toList());
});

final reportsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.contentReports).where('campusId', isEqualTo: campusId).where('status', isEqualTo: 'open').orderBy('createdAt', descending: true).limit(100).snapshots().map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

final campusMembersProvider = StreamProvider<List<Membership>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.memberships).where('campusId', isEqualTo: campusId).orderBy('joinedAt', descending: true).limit(1000).snapshots().map((s) => s.docs.map(Membership.fromDoc).toList());
});

final auditLogsProvider = StreamProvider<List<AuditLog>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.auditLogs).where('campusId', isEqualTo: campusId).orderBy('at', descending: true).limit(200).snapshots().map((s) => s.docs.map(AuditLog.fromDoc).toList());
});

final campusRedemptionsProvider = StreamProvider<List<Redemption>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.redemptions).where('campusId', isEqualTo: campusId).orderBy('issuedAt', descending: true).limit(300).snapshots().map((s) => s.docs.map(Redemption.fromDoc).toList());
});

final campusSurveysProvider = StreamProvider<List<Survey>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.surveys).where('campusId', isEqualTo: campusId).orderBy('createdAt', descending: true).snapshots().map((s) => s.docs.map(Survey.fromDoc).toList());
});

final adminQuestsProvider = StreamProvider<List<Quest>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.quests).where('campusIds', arrayContains: campusId).where('status', whereIn: ['submitted', 'approved', 'live', 'paused', 'completed', 'cancelled']).snapshots().map((s) => (s.docs.map(Quest.fromDoc).toList())..sort((a, b) => a.status == 'submitted' ? -1 : b.status == 'submitted' ? 1 : b.startAt.compareTo(a.startAt)));
});

final supportRequestsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.supportRequests).where('campusId', isEqualTo: campusId).where('status', isEqualTo: 'open').limit(100).snapshots().map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

final qrSessionsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.eventQrSessions).where('campusId', isEqualTo: campusId).limit(200).snapshots().map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

Future<void> _call(BuildContext context, WidgetRef ref, String fn, Map<String, dynamic> data, String ok) async {
  try { await ref.read(functionsProvider).call(fn, data); if (context.mounted) showCbSnack(context, ok); } catch (e) { if (context.mounted) showCbError(context, e); }
}

/* ------------------------------------------------------------------ */
/* Dashboard                                                           */
/* ------------------------------------------------------------------ */

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(campusDashboardProvider);
    final campus = ref.watch(campusProvider).value;
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Campus dashboard',
      subtitle: campus?.name,
      actions: [
        OutlinedButton.icon(onPressed: () async { await _call(context, ref, 'runMetricsAggregation', {'campusId': campus?.id, 'days': 14}, 'Metrics recomputed.'); ref.invalidate(campusDashboardProvider); }, icon: const Icon(Icons.calculate_outlined, size: 18), label: const Text('Recompute')),
        OutlinedButton.icon(onPressed: () async { await _call(context, ref, 'runMaintenanceNow', {'campusId': campus?.id}, 'Sweeps ran (closures, expiry, notifications).'); ref.invalidate(campusDashboardProvider); }, icon: const Icon(Icons.cleaning_services_outlined, size: 18), label: const Text('Run sweeps')),
        FilledButton.icon(onPressed: () => ref.invalidate(campusDashboardProvider), icon: const Icon(Icons.refresh), label: const Text('Refresh')),
      ],
      child: d.when(
        loading: () => const CbLoading(message: 'Computing live metrics from Firestore…'),
        error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(campusDashboardProvider)),
        data: (a) {
          final warnings = (a['warnings'] as List).map((w) => Map<String, dynamic>.from(w as Map)).toList();
          final daily = (a['daily'] as List).map((w) => Map<String, dynamic>.from(w as Map)).toList();
          final econ = Map<String, dynamic>.from(a['economy'] as Map);
          final rr = Map<String, dynamic>.from(econ['redemptionRate'] as Map);
          final retention = Map<String, dynamic>.from(a['retention'] as Map);
          final survey = Map<String, dynamic>.from(a['survey'] as Map);
          final buzz = a['buzzScore'] == null ? null : Map<String, dynamic>.from(a['buzzScore'] as Map);
          final targets = Map<String, dynamic>.from(a['targets'] as Map);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (warnings.isNotEmpty) ...[for (final w in warnings) Padding(padding: const EdgeInsets.only(bottom: 8), child: CbCard(padding: const EdgeInsets.all(12), borderColor: CbColors.warning, child: Row(children: [const Icon(Icons.warning_amber_rounded, color: CbColors.warning), const SizedBox(width: 10), Expanded(child: Text(w['message'] as String, style: t.bodyMedium)), Text(w['code'] as String, style: t.labelSmall)]))), const SizedBox(height: 8)],
            Text('Live values from stored data. Targets are shown separately and labelled.', style: t.bodySmall),
            const SizedBox(height: 8),
            CbStatGrid(children: [
              CbStat(label: 'Registered students', value: '${a['registered']}', hint: 'target ${targets['registrations']}+', icon: Icons.people_outline),
              CbStat(label: 'WAP (this week)', value: '${a['wap']}', hint: '${a['wapPercent']}% of registered · target ${targets['wapPercent']}%', icon: Icons.local_fire_department, color: CbColors.limeText),
              CbStat(label: 'Active organizers', value: '${a['activeOrganizers']}', hint: 'posted this week · target ${targets['organizersMin']}+', icon: Icons.groups_outlined),
              CbStat(label: 'Events this week', value: '${a['eventsThisWeek']}', hint: '${a['eventsNext7Days']} in next 7d · ${a['eventsTodayTomorrow']} today/tomorrow', icon: Icons.event),
              CbStat(label: 'RSVPs / check-ins', value: '${a['rsvpsThisWeek']} / ${a['checkinsThisWeek']}', hint: 'this week', icon: Icons.how_to_reg),
              CbStat(label: 'RSVP → attendance', value: Fmt.pct((a['rsvpToAttendance'] as Map)['pct'] as num?), hint: 'last 30 days, ${(a['rsvpToAttendance'] as Map)['events']} events', icon: Icons.trending_up),
              CbStat(label: 'Redemption rate', value: Fmt.pct(rr['byCoins'] as num?), hint: '${Fmt.pct(rr['byUsers'] as num?)} of earners redeemed', icon: Icons.card_giftcard_outlined),
              CbStat(label: 'Week-6 retention', value: retention['ready'] == true ? Fmt.pct(retention['participation'] as num?) : 'n/a yet', hint: retention['ready'] == true ? 'participation · product ${Fmt.pct(retention['product'] as num?)}' : 'needs 6 weeks of data', icon: Icons.repeat),
              CbStat(label: 'NPS', value: survey['nps'] == null ? '—' : '${survey['nps']}', hint: '${survey['responses']} responses', icon: Icons.thumb_up_outlined),
              CbStat(label: 'Pending review', value: '${a['pendingReview']}', hint: '${a['pendingRoleRequests']} role requests', icon: Icons.rule_folder_outlined, onTap: () => context.go('/admin/review')),
            ]),
            const SizedBox(height: 16),
            if (buzz != null) CbCard(child: Row(children: [
              Column(children: [Text('${buzz['score']}', style: t.displaySmall?.copyWith(color: CbColors.limeText)), Text('Campus Buzz Score', style: t.labelMedium)]),
              const SizedBox(width: 24),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final c in (buzz['components'] as List)) Text('${c['key']}: ${((c['normalized'] as num) * 100).round()}% × ${c['weight']} = ${c['contribution']} pts', style: t.bodySmall), Text('Transparent weighted score — not an accreditation metric. Formula in docs/ANALYTICS.md.', style: t.bodySmall?.copyWith(color: CbColors.textTertiary))])),
            ])),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, c) {
              final charts = [
                CbLineChart(title: 'WAP trend', period: 'last ${daily.length} days', points: daily.map((x) => ((x['wap'] as num?) ?? 0).toDouble()).toList(), labels: daily.map((x) => (x['date'] as String).substring(5)).toList()),
                CbBarChart(title: 'RSVPs vs check-ins', period: 'per day', values: daily.map((x) => ((x['rsvps'] as num?) ?? 0).toDouble()).toList(), secondary: daily.map((x) => ((x['checkins'] as num?) ?? 0).toDouble()).toList(), labels: daily.map((x) => (x['date'] as String).substring(8)).toList(), primaryLabel: 'RSVPs', secondaryLabel: 'Check-ins'),
              ];
              return c.maxWidth > 900 ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final ch in charts) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: ch))]) : Column(children: [for (final ch in charts) Padding(padding: const EdgeInsets.only(bottom: 12), child: ch)]);
            }),
            const SizedBox(height: 16),
            Text('BuzzCoin economy health', style: t.titleLarge),
            const SizedBox(height: 8),
            CbStatGrid(children: [
              CbStat(label: 'Earned (30d)', value: Fmt.coins(econ['coinsEarnedMonth'] as num), icon: Icons.add_circle_outline),
              CbStat(label: 'Redeemed (30d)', value: Fmt.coins(econ['coinsRedeemedMonth'] as num), icon: Icons.remove_circle_outline),
              CbStat(label: 'Outstanding', value: Fmt.coins(econ['outstanding'] as num), hint: 'coins in circulation', icon: Icons.account_balance_wallet_outlined),
              CbStat(label: 'Avg weekly earn / user', value: '${econ['avgWeeklyEarnPerUser']}', hint: 'healthy ${(econ['thresholds'] as Map)['weeklyEarnHealthyMin']}–${(econ['thresholds'] as Map)['weeklyEarnHealthyMax']}, warn >${(econ['thresholds'] as Map)['weeklyEarnWarning']}', icon: Icons.speed, band: (econ['avgWeeklyEarnPerUser'] as num) > ((econ['thresholds'] as Map)['weeklyEarnWarning'] as num) ? 'red' : (econ['avgWeeklyEarnPerUser'] as num) == 0 ? null : 'green'),
              CbStat(label: 'Redeemable inventory', value: '${Fmt.coins(econ['redeemableInventoryCoins'] as num)} coins', hint: '≈ ${Fmt.rupees(econ['redeemableInventoryValue'] as num)} face value', icon: Icons.inventory_2_outlined),
              CbStat(label: 'Earned ÷ redeemable', value: '${econ['earnedToRedeemableRatio']}×', hint: 'warn above ${(econ['thresholds'] as Map)['maxEarnedToRedeemableRatio']}×', icon: Icons.balance, band: (econ['earnedToRedeemableRatio'] as num) > ((econ['thresholds'] as Map)['maxEarnedToRedeemableRatio'] as num) ? 'red' : 'green'),
            ]),
            const SizedBox(height: 8),
            Text('QR scans: ${(a['qr'] as Map)['scanSuccesses']} ok / ${(a['qr'] as Map)['scanFailures']} failed. Generated ${a['generatedAt']}.', style: t.bodySmall),
          ]);
        },
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/* Pilot scorecard                                                     */
/* ------------------------------------------------------------------ */

class PilotScorecardScreen extends ConsumerWidget {
  const PilotScorecardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(campusDashboardProvider);
    final history = ref.watch(pilotHistoryProvider).value ?? const [];
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'JAGSoM pilot scorecard',
      subtitle: 'Prove CampusBuzz improves discovery and attendance. Green only when real data meets the threshold.',
      actions: [OutlinedButton.icon(onPressed: () => ref.invalidate(campusDashboardProvider), icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh'))],
      child: d.when(
        loading: () => const CbLoading(),
        error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(campusDashboardProvider)),
        data: (a) {
          final rows = (a['scorecard'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
          final targets = Map<String, dynamic>.from(a['targets'] as Map);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CbCard(padding: const EdgeInsets.all(12), child: Wrap(spacing: 16, runSpacing: 6, children: [Text('TARGETS (not results):', style: t.labelSmall), Text('${targets['registrations']}+ students', style: t.bodySmall), Text('${targets['organizersMin']}–${targets['organizersMax']} organizers', style: t.bodySmall), Text('${targets['wapPercent']}%+ WAP', style: t.bodySmall), Text('${targets['initialEventSupply']}+ events at launch', style: t.bodySmall), Text('${targets['redemptionOptionsBeforeLaunch']}+ rewards before reward launch', style: t.bodySmall)])),
            const SizedBox(height: 12),
            for (final r in rows)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: CbCard(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Row(children: [
                Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r['label'] as String, style: t.titleMedium), Text('Red < ${r['redBelow']}${r['unit'] == 'percent' ? '%' : ''} · Yellow to ${r['greenAtOrAbove']}${r['unit'] == 'percent' ? '%' : ''} · Green ≥ ${r['greenAtOrAbove']}${r['unit'] == 'percent' ? '%' : ''}', style: t.bodySmall)])),
                Expanded(flex: 2, child: Text(r['value'] == null ? 'No data' : r['unit'] == 'percent' ? Fmt.pct(r['value'] as num, digits: 1) : '${r['value']}', style: t.headlineSmall, textAlign: TextAlign.end)),
                const SizedBox(width: 16),
                bandPill(r['band'] as String),
              ]))),
            const SizedBox(height: 16),
            Text('Weekly history', style: t.titleLarge),
            const SizedBox(height: 4),
            Text('Snapshots taken every Monday 03:00 campus time.', style: t.bodySmall),
            const SizedBox(height: 8),
            if (history.isEmpty) Text('No snapshots yet — the first one lands next Monday.', style: t.bodyMedium)
            else CbLineChart(title: 'WAP % by week', points: history.reversed.map((h) => (((h['raw'] as Map)['wapPercent'] as num?) ?? 0).toDouble()).toList(), labels: history.reversed.map((h) => (h['weekKey'] as String).split('-W').last).toList(), unit: '%'),
            const SizedBox(height: 8),
            if (history.isNotEmpty) SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('Week')), DataColumn(label: Text('Students')), DataColumn(label: Text('WAP %')), DataColumn(label: Text('Organizers')), DataColumn(label: Text('RSVP→Att')), DataColumn(label: Text('NPS'))], rows: [for (final h in history) DataRow(cells: [DataCell(Text(h['weekKey'] as String)), for (final k in ['registeredStudents', 'wapPercent', 'organizersPostingWeekly', 'rsvpToAttendance', 'nps']) DataCell(Builder(builder: (_) { final row = (h['rows'] as List).cast<Map>().firstWhere((r) => r['key'] == k, orElse: () => {}); return Row(mainAxisSize: MainAxisSize.min, children: [Text(row['value'] == null ? '—' : '${row['value']}'), const SizedBox(width: 6), if (row['band'] != null) Icon(switch (row['band']) { 'green' => Icons.check_circle, 'yellow' => Icons.warning_amber_rounded, 'red' => Icons.error, _ => Icons.help_outline }, size: 14, color: CbColors.bandColor(row['band'] as String))]); }))])])),
          ]);
        },
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/* Event review + reports                                              */
/* ------------------------------------------------------------------ */

class EventReviewScreen extends ConsumerWidget {
  const EventReviewScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(reviewQueueProvider);
    final reports = ref.watch(reportsProvider).value ?? const [];
    final support = ref.watch(supportRequestsProvider).value ?? const [];
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Event review queue',
      subtitle: 'Events go live immediately. Review within the operating SLA; unpublish only for a serious reason.',
      child: queue.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (list.isEmpty) const CbEmpty(icon: Icons.task_alt, title: 'Queue is clear'),
          for (final e in list)
            Padding(padding: const EdgeInsets.only(bottom: 10), child: CbCard(borderColor: e.reviewStatus == 'flagged' ? CbColors.warning : null, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(e.title, style: t.titleMedium)), CbStatusPill(label: e.reviewStatus == 'flagged' ? 'Flagged · ${e.reportCount} report${e.reportCount == 1 ? '' : 's'}' : 'Pending review', color: e.reviewStatus == 'flagged' ? CbColors.warning : CbColors.info, icon: e.reviewStatus == 'flagged' ? Icons.flag : Icons.schedule)]),
              Text('${e.clubName} · ${Fmt.dateTime(e.startAt, tz)} · ${e.location.name} · ${e.stats.rsvpCount} RSVPs', style: t.bodySmall),
              const SizedBox(height: 6),
              Text(e.description, style: t.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
              for (final r in reports.where((r) => r['entityId'] == e.id)) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Report: ${r['reason']}', style: t.bodySmall?.copyWith(color: CbColors.warning))),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                TextButton(onPressed: () => context.push('/events/${e.id}'), child: const Text('Open')),
                FilledButton.tonal(onPressed: () => _call(context, ref, 'reviewEvent', {'eventId': e.id, 'decision': 'approved'}, 'Approved.'), child: const Text('Approve')),
                OutlinedButton(onPressed: () async { final r = await askReason(context, title: 'Flag for follow-up', required: false); if (r != null) _call(context, ref, 'reviewEvent', {'eventId': e.id, 'decision': 'flagged', 'reason': r}, 'Flagged.'); }, child: const Text('Flag')),
                TextButton(style: TextButton.styleFrom(foregroundColor: CbColors.danger), onPressed: () async { final r = await askReason(context, title: 'Unpublish event', hint: 'Reason (students who RSVP\'d are notified)'); if (r != null) _call(context, ref, 'reviewEvent', {'eventId': e.id, 'decision': 'unpublished', 'reason': r}, 'Unpublished and RSVPs notified.'); }, child: const Text('Unpublish')),
              ]),
            ]))),
          const SizedBox(height: 16),
          Text('Open support requests (${support.length})', style: t.titleLarge),
          const SizedBox(height: 8),
          for (final s in support) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.support_agent), title: Text(s['message'] as String? ?? ''), subtitle: Text('uid ${(s['uid'] as String? ?? '').substring(0, 8)}…'), trailing: TextButton(onPressed: () => ref.read(firestoreProvider).collection(Col.supportRequests).doc(s['id'] as String).update({'status': 'resolved', 'respondedAt': FieldValue.serverTimestamp()}), child: const Text('Resolve'))),
        ]),
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/* Organizers & roles / Users                                          */
/* ------------------------------------------------------------------ */

class OrganizersScreen extends ConsumerWidget {
  const OrganizersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(campusMembersProvider);
    final clubs = ref.watch(clubsProvider).value ?? const <Club>[];
    final events = ref.watch(upcomingEventsProvider).value ?? const <Event>[];
    final campusId = ref.watch(activeCampusIdProvider);
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Organizers & roles',
      actions: [FilledButton.icon(onPressed: () => _clubDialog(context, ref, campusId!), icon: const Icon(Icons.add), label: const Text('New club'))],
      child: members.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) {
          final pending = list.where((m) => m.requestedRoles.isNotEmpty).toList();
          final organizers = list.where((m) => m.has(Role.organizer)).toList();
          final activeClubIds = {for (final e in events) e.clubId};
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Access requests (${pending.length})', style: t.titleLarge),
            const SizedBox(height: 8),
            if (pending.isEmpty) Text('No pending requests.', style: t.bodyMedium),
            for (final m in pending) for (final role in m.requestedRoles)
              CbCard(padding: const EdgeInsets.all(12), child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${m.displayName} → $role', style: t.titleSmall), Text('${(m.roleRequests[role] as Map?)?['clubName'] ?? ''} ${(m.roleRequests[role] as Map?)?['note'] ?? ''}'.trim(), style: t.bodySmall)])),
                if (role == 'organizer') _ClubSelect(clubs: clubs, onGrant: (clubId) => _call(context, ref, 'setMembershipRole', {'campusId': campusId, 'uid': m.uid, 'role': 'organizer', 'grant': true, 'clubId': clubId, 'reason': 'Approved organizer request'}, 'Organizer approved.'))
                else FilledButton.tonal(onPressed: () => _call(context, ref, 'setMembershipRole', {'campusId': campusId, 'uid': m.uid, 'role': role, 'grant': true, 'reason': 'Approved request'}, 'Approved.'), child: const Text('Approve')),
                TextButton(onPressed: () => _call(context, ref, 'setMembershipRole', {'campusId': campusId, 'uid': m.uid, 'role': role, 'grant': false, 'reason': 'Declined request'}, 'Declined.'), child: const Text('Decline')),
              ])),
            const SizedBox(height: 20),
            Text('Clubs (${clubs.length})', style: t.titleLarge),
            const SizedBox(height: 8),
            for (final c in clubs) ListTile(contentPadding: EdgeInsets.zero, leading: Icon(activeClubIds.contains(c.id) ? Icons.check_circle : Icons.circle_outlined, color: activeClubIds.contains(c.id) ? CbColors.success : CbColors.textTertiary), title: Text(c.name), subtitle: Text('${c.category} · ${c.adminUids.length} organizer${c.adminUids.length == 1 ? '' : 's'} · ${activeClubIds.contains(c.id) ? 'has upcoming events' : 'no upcoming events — posting consistency risk'}'), trailing: IconButton(onPressed: () => _clubDialog(context, ref, campusId!, club: c), icon: const Icon(Icons.edit_outlined))),
            const SizedBox(height: 20),
            Text('Organizers (${organizers.length})', style: t.titleLarge),
            const SizedBox(height: 8),
            for (final m in organizers) ListTile(contentPadding: EdgeInsets.zero, leading: CbAvatar(name: m.displayName, size: 32), title: Text(m.displayName), subtitle: Text(m.clubIds.map((id) => clubs.firstWhere((c) => c.id == id, orElse: () => Club(id: id, campusId: '', name: id)).name).join(', ')), trailing: Wrap(spacing: 4, children: [
              _ClubSelect(clubs: clubs, label: 'Add club', onGrant: (clubId) => _call(context, ref, 'setMembershipRole', {'campusId': campusId, 'uid': m.uid, 'role': 'organizer', 'grant': true, 'clubId': clubId, 'reason': 'Added club'}, 'Club added.')),
              TextButton(style: TextButton.styleFrom(foregroundColor: CbColors.danger), onPressed: () async { final r = await askReason(context, title: 'Revoke organizer access'); if (r != null) _call(context, ref, 'setMembershipRole', {'campusId': campusId, 'uid': m.uid, 'role': 'organizer', 'grant': false, 'reason': r}, 'Revoked.'); }, child: const Text('Revoke')),
            ])),
          ]);
        },
      ),
    );
  }

  Future<void> _clubDialog(BuildContext context, WidgetRef ref, String campusId, {Club? club}) async {
    final name = TextEditingController(text: club?.name ?? ''), desc = TextEditingController(text: club?.description ?? ''), cat = TextEditingController(text: club?.category ?? '');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(club == null ? 'New club' : 'Edit club'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), TextField(controller: cat, decoration: const InputDecoration(labelText: 'Category')), TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))]));
    if (ok == true && context.mounted) _call(context, ref, 'upsertClub', {'campusId': campusId, 'clubId': club?.id, 'name': name.text.trim(), 'category': cat.text.trim(), 'description': desc.text.trim()}, 'Club saved.');
  }
}

class _ClubSelect extends StatelessWidget {
  const _ClubSelect({required this.clubs, required this.onGrant, this.label = 'Approve → club'});
  final List<Club> clubs; final ValueChanged<String> onGrant; final String label;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(onSelected: onGrant, itemBuilder: (_) => [for (final c in clubs) PopupMenuItem(value: c.id, child: Text(c.name))], child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: CbColors.limeText)), const Icon(Icons.arrow_drop_down, color: CbColors.limeText)])));
}

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final members = ref.watch(campusMembersProvider);
    final campusId = ref.watch(activeCampusIdProvider);
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Users',
      subtitle: 'Suspension requires a reason and is audited. Nothing here is destructive.',
      child: members.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) {
          final filtered = list.where((m) => _q.isEmpty || m.displayName.toLowerCase().contains(_q) || m.uid.contains(_q)).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(onChanged: (v) => setState(() => _q = v.toLowerCase()), decoration: const InputDecoration(hintText: 'Search by name or uid', prefixIcon: Icon(Icons.search))),
            const SizedBox(height: 8),
            Text('${filtered.length} of ${list.length} members', style: t.bodySmall),
            const SizedBox(height: 8),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('Name')), DataColumn(label: Text('Roles')), DataColumn(label: Text('Status')), DataColumn(label: Text('Joined')), DataColumn(label: Text('Actions'))], rows: [
              for (final m in filtered.take(200)) DataRow(cells: [
                DataCell(Text(m.displayName)),
                DataCell(Text(m.roles.map((r) => r.label).join(', '))),
                DataCell(CbStatusPill(label: m.status, color: m.status == 'active' ? CbColors.success : CbColors.danger)),
                DataCell(Text(m.joinedAt == null ? '' : Fmt.date(m.joinedAt!, tz))),
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  if (m.status == 'active') TextButton(style: TextButton.styleFrom(foregroundColor: CbColors.danger), onPressed: () async { final r = await askReason(context, title: 'Suspend ${m.displayName}', hint: 'Reason (shown to the student, recorded in audit log)'); if (r != null && context.mounted) _call(context, ref, 'setUserSuspension', {'campusId': campusId, 'uid': m.uid, 'suspend': true, 'reason': r}, 'Suspended.'); }, child: const Text('Suspend'))
                  else TextButton(onPressed: () async { final r = await askReason(context, title: 'Reactivate ${m.displayName}'); if (r != null && context.mounted) _call(context, ref, 'setUserSuspension', {'campusId': campusId, 'uid': m.uid, 'suspend': false, 'reason': r}, 'Reactivated.'); }, child: const Text('Reactivate')),
                  TextButton(onPressed: () async { final r = await askReason(context, title: 'Adjust BuzzCoins for ${m.displayName}', hint: 'amount (e.g. -20 or 15) | reason'); if (r == null) return; final parts = r.split('|'); final amt = int.tryParse(parts.first.trim()); if (amt == null || parts.length < 2) { if (context.mounted) showCbSnack(context, 'Format: amount | reason', error: true); return; } if (context.mounted) _call(context, ref, 'adminAdjustCoins', {'campusId': campusId, 'uid': m.uid, 'amount': amt, 'reason': parts.sublist(1).join('|').trim()}, 'Adjusted (ledger + audit).'); }, child: const Text('Coins')),
                  if (!m.has(Role.ambassador)) TextButton(onPressed: () => _call(context, ref, 'setMembershipRole', {'campusId': campusId, 'uid': m.uid, 'role': 'ambassador', 'grant': true, 'reason': 'Made ambassador'}, 'Ambassador granted.'), child: const Text('Make ambassador')),
                ])),
              ]),
            ])),
          ]);
        },
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/* Rewards / Vendors / Redemptions                                     */
/* ------------------------------------------------------------------ */

class AdminRewardsScreen extends ConsumerWidget {
  const AdminRewardsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rewards = ref.watch(allRewardsProvider);
    final vendors = ref.watch(vendorsProvider).value ?? const <Vendor>[];
    final campusId = ref.watch(activeCampusIdProvider);
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Rewards',
      subtitle: 'Inventory changes are audited. Keep ≥3 live options before promoting BuzzCoins.',
      actions: [FilledButton.icon(onPressed: () => _rewardDialog(context, ref, campusId!, vendors), icon: const Icon(Icons.add), label: const Text('New reward'))],
      child: rewards.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CbStatGrid(children: [CbStat(label: 'Active rewards', value: '${list.where((r) => r.status == 'active').length}', icon: Icons.card_giftcard, band: list.where((r) => r.status == 'active').length >= 3 ? 'green' : 'red'), CbStat(label: 'Redeemable inventory', value: '${list.fold<int>(0, (s, r) => s + (r.inventory ?? 0))}', icon: Icons.inventory_2_outlined), CbStat(label: 'Total redeemed', value: '${list.fold<int>(0, (s, r) => s + r.redeemed)}', icon: Icons.done_all)]),
          const SizedBox(height: 16),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('Reward')), DataColumn(label: Text('Type')), DataColumn(label: Text('Cost')), DataColumn(label: Text('Inventory')), DataColumn(label: Text('Face value')), DataColumn(label: Text('Redeemed')), DataColumn(label: Text('Status')), DataColumn(label: Text(''))], rows: [
            for (final r in list) DataRow(cells: [DataCell(Text(r.title)), DataCell(Text(r.typeLabel)), DataCell(Text('${r.coinCost}')), DataCell(Text(r.inventory == null ? '∞' : '${r.inventory}', style: TextStyle(color: r.soldOut ? CbColors.danger : null))), DataCell(Text(r.faceValue == null ? '—' : Fmt.rupees(r.faceValue!))), DataCell(Text('${r.redeemed}')), DataCell(CbStatusPill(label: r.status, color: r.status == 'active' ? CbColors.success : CbColors.textTertiary)), DataCell(IconButton(onPressed: () => _rewardDialog(context, ref, campusId!, vendors, reward: r), icon: const Icon(Icons.edit_outlined)))]),
          ])),
          const SizedBox(height: 8),
          Text('Economics rule: monthly coins earned should stay under ~3× redeemable value. See dashboard warnings.', style: t.bodySmall),
        ]),
      ),
    );
  }

  Future<void> _rewardDialog(BuildContext context, WidgetRef ref, String campusId, List<Vendor> vendors, {Reward? reward}) async {
    final title = TextEditingController(text: reward?.title ?? ''), desc = TextEditingController(text: reward?.description ?? ''), cost = TextEditingController(text: '${reward?.coinCost ?? 100}'), inv = TextEditingController(text: reward?.inventory?.toString() ?? '50'), face = TextEditingController(text: reward?.faceValue?.toString() ?? ''), instr = TextEditingController(text: reward?.redemptionInstructions ?? ''), terms = TextEditingController(text: reward?.terms ?? ''), limit = TextEditingController(text: '${reward?.perUserLimit ?? 0}');
    var type = reward?.type ?? 'voucher'; var status = reward?.status ?? 'active'; String? vendorId = reward?.vendorId;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(
      title: Text(reward == null ? 'New reward' : 'Edit reward'),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')),
        DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Type'), items: const [DropdownMenuItem(value: 'voucher', child: Text('Voucher')), DropdownMenuItem(value: 'printing_credit', child: Text('Printing credit')), DropdownMenuItem(value: 'priority_access', child: Text('Priority access')), DropdownMenuItem(value: 'merchandise', child: Text('Merchandise')), DropdownMenuItem(value: 'certificate', child: Text('Certificate')), DropdownMenuItem(value: 'generic', child: Text('Generic'))], onChanged: (v) => setState(() => type = v!)),
        Row(children: [Expanded(child: TextField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Coin cost'))), const SizedBox(width: 8), Expanded(child: TextField(controller: inv, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Inventory (blank = ∞)'))), const SizedBox(width: 8), Expanded(child: TextField(controller: face, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Face value ₹')))]),
        DropdownButtonFormField<String?>(initialValue: vendorId, decoration: const InputDecoration(labelText: 'Vendor'), items: [const DropdownMenuItem(value: null, child: Text('None (internal)')), for (final v in vendors) DropdownMenuItem(value: v.id, child: Text(v.name))], onChanged: (v) => setState(() => vendorId = v)),
        TextField(controller: instr, decoration: const InputDecoration(labelText: 'Redemption instructions')),
        TextField(controller: terms, decoration: const InputDecoration(labelText: 'Terms')),
        Row(children: [Expanded(child: TextField(controller: limit, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Per-user limit (0 = none)'))), const SizedBox(width: 8), Expanded(child: DropdownButtonFormField<String>(initialValue: status, decoration: const InputDecoration(labelText: 'Status'), items: const [DropdownMenuItem(value: 'active', child: Text('Active')), DropdownMenuItem(value: 'inactive', child: Text('Inactive'))], onChanged: (v) => setState(() => status = v!)))]),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
    )));
    if (ok == true && context.mounted) _call(context, ref, 'upsertReward', {'campusId': campusId, 'rewardId': reward?.id, 'title': title.text.trim(), 'description': desc.text.trim(), 'type': type, 'coinCost': int.tryParse(cost.text) ?? 0, 'inventory': inv.text.trim().isEmpty ? null : int.tryParse(inv.text), 'faceValue': double.tryParse(face.text), 'vendorId': vendorId, 'redemptionInstructions': instr.text.trim(), 'terms': terms.text.trim(), 'perUserLimit': int.tryParse(limit.text) ?? 0, 'status': status}, 'Reward saved (audited).');
  }
}

class VendorsScreen extends ConsumerWidget {
  const VendorsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(vendorsProvider);
    final redemptions = ref.watch(campusRedemptionsProvider).value ?? const <Redemption>[];
    final campusId = ref.watch(activeCampusIdProvider);
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Vendors & settlement',
      actions: [FilledButton.icon(onPressed: () => _vendorDialog(context, ref, campusId!), icon: const Icon(Icons.add), label: const Text('New vendor'))],
      child: vendors.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final v in list) ...[
            CbCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Expanded(child: Text(v.name, style: t.titleLarge)), CbStatusPill(label: v.status, color: v.status == 'active' ? CbColors.success : CbColors.textTertiary), IconButton(onPressed: () => _vendorDialog(context, ref, campusId!, vendor: v), icon: const Icon(Icons.edit_outlined))]),
              Text('${v.contact} · fulfilled ${v.fulfilled} · pending settlement ${Fmt.rupees(v.pendingSettlementValue)}', style: t.bodySmall),
              const SizedBox(height: 8),
              Builder(builder: (_) {
                final months = <String, ({int count, num value, int pending})>{};
                for (final r in redemptions.where((r) => r.vendorId == v.id && r.status == 'fulfilled')) { final k = r.settlementMonth ?? '?'; final c = months[k] ?? (count: 0, value: 0, pending: 0); months[k] = (count: c.count + 1, value: c.value + (r.faceValue ?? 0), pending: c.pending + (r.settlementStatus == 'pending' ? 1 : 0)); }
                final keys = months.keys.toList()..sort((a, b) => b.compareTo(a));
                return Column(children: [for (final m in keys) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text('$m · ${months[m]!.count} redemptions · ${Fmt.rupees(months[m]!.value)}'), trailing: months[m]!.pending == 0 ? const CbStatusPill(label: 'Settled', color: CbColors.success, icon: Icons.check) : FilledButton.tonal(onPressed: () async { if (await confirm(context, title: 'Mark $m settled for ${v.name}?', message: '${months[m]!.pending} pending redemptions · ${Fmt.rupees(months[m]!.value)}')) _call(context, ref, 'settleVendorMonth', {'campusId': campusId, 'vendorId': v.id, 'month': m}, 'Settled.'); }, child: Text('Settle ${months[m]!.pending}')))]);
              }),
            ])),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          Text('Recent redemptions', style: t.titleLarge),
          const SizedBox(height: 8),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('Code')), DataColumn(label: Text('Reward')), DataColumn(label: Text('Vendor')), DataColumn(label: Text('Coins')), DataColumn(label: Text('Status')), DataColumn(label: Text('Issued')), DataColumn(label: Text(''))], rows: [
            for (final r in redemptions.take(60)) DataRow(cells: [DataCell(Text(r.code)), DataCell(Text(r.rewardTitle)), DataCell(Text(r.vendorId ?? '—')), DataCell(Text('${r.coinCost}')), DataCell(Text(r.status)), DataCell(Text(r.issuedAt == null ? '' : Fmt.date(r.issuedAt!, tz))), DataCell(r.status == 'issued' ? TextButton(onPressed: () async { final reason = await askReason(context, title: 'Refund ${r.code}?'); if (reason != null && context.mounted) _call(context, ref, 'refundRedemption', {'redemptionId': r.id, 'reason': reason}, 'Refunded.'); }, child: const Text('Refund')) : const SizedBox.shrink())]),
          ])),
        ]),
      ),
    );
  }

  Future<void> _vendorDialog(BuildContext context, WidgetRef ref, String campusId, {Vendor? vendor}) async {
    final name = TextEditingController(text: vendor?.name ?? ''), contact = TextEditingController(text: vendor?.contact ?? '');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(vendor == null ? 'New vendor' : 'Edit vendor'), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), TextField(controller: contact, decoration: const InputDecoration(labelText: 'Contact'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))]));
    if (ok == true && context.mounted) _call(context, ref, 'upsertVendor', {'campusId': campusId, 'vendorId': vendor?.id, 'name': name.text.trim(), 'contact': contact.text.trim()}, 'Vendor saved. Grant a login the vendor role in Users → Roles with this vendor id: ${vendor?.id ?? '(new)'}');
  }
}

/* ------------------------------------------------------------------ */
/* QR / fraud review                                                   */
/* ------------------------------------------------------------------ */

class FraudReviewScreen extends ConsumerWidget {
  const FraudReviewScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(qrSessionsProvider).value ?? const [];
    final audit = ref.watch(auditLogsProvider).value ?? const <AuditLog>[];
    final redemptions = ref.watch(campusRedemptionsProvider).value ?? const <Redemption>[];
    final t = Theme.of(context).textTheme;
    final manualByActor = <String, int>{};
    for (final a in audit.where((a) => a.action == 'checkin.manual')) manualByActor[a.actorUid] = (manualByActor[a.actorUid] ?? 0) + 1;
    final heavyManual = manualByActor.entries.where((e) => e.value >= 10).toList()..sort((a, b) => b.value.compareTo(a.value));
    final failing = sessions.where((s) => ((s['scanFailures'] as num?) ?? 0) >= 5 && ((s['scanFailures'] as num?) ?? 0) > ((s['scanSuccesses'] as num?) ?? 0) * 0.3).toList();
    final byUser = <String, int>{};
    for (final r in redemptions.where((r) => r.issuedAt != null && r.issuedAt!.isAfter(DateTime.now().toUtc().subtract(const Duration(days: 7))))) byUser[r.uid] = (byUser[r.uid] ?? 0) + 1;
    final heavyRedeem = byUser.entries.where((e) => e.value >= 5).toList();
    return CbPage(
      title: 'QR & fraud review',
      subtitle: 'Signals for humans to review. Nothing here accuses or punishes automatically.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CbStatGrid(children: [CbStat(label: 'Manual check-ins (recent)', value: '${audit.where((a) => a.action == 'checkin.manual').length}', icon: Icons.how_to_reg), CbStat(label: 'Organizers ≥10 manual', value: '${heavyManual.length}', icon: Icons.person_search, band: heavyManual.isEmpty ? 'green' : 'yellow'), CbStat(label: 'Events with QR failures', value: '${failing.length}', icon: Icons.qr_code_2, band: failing.isEmpty ? 'green' : 'yellow'), CbStat(label: 'Heavy redeemers (7d)', value: '${heavyRedeem.length}', icon: Icons.card_giftcard, band: heavyRedeem.isEmpty ? 'green' : 'yellow')]),
        const SizedBox(height: 16),
        Text('Excessive manual check-ins', style: t.titleLarge),
        if (heavyManual.isEmpty) Text('None flagged.', style: t.bodyMedium),
        for (final e in heavyManual) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.how_to_reg, color: CbColors.warning), title: Text('Organizer ${e.key.substring(0, 8)}…'), subtitle: Text('${e.value} manual check-ins in the recent audit window')),
        const SizedBox(height: 16),
        Text('QR scan failures', style: t.titleLarge),
        if (failing.isEmpty) Text('No events with unusual failure rates.', style: t.bodyMedium),
        for (final s in failing) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.qr_code_2, color: CbColors.warning), title: Text('Event ${s['id']}'), subtitle: Text('${s['scanFailures']} failed / ${s['scanSuccesses']} ok'), trailing: TextButton(onPressed: () => context.push('/events/${s['id']}'), child: const Text('Open'))),
        const SizedBox(height: 16),
        Text('Unusual redemption volume', style: t.titleLarge),
        if (heavyRedeem.isEmpty) Text('None.', style: t.bodyMedium),
        for (final e in heavyRedeem) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.card_giftcard, color: CbColors.warning), title: Text('Student ${e.key.substring(0, 8)}…'), subtitle: Text('${e.value} redemptions in 7 days')),
        const SizedBox(height: 16),
        Text('Duplicates are impossible by construction (deterministic ids + idempotent ledger keys). Review the audit log for manual corrections.', style: t.bodySmall),
      ]),
    );
  }
}

/* ------------------------------------------------------------------ */
/* Notification composer                                               */
/* ------------------------------------------------------------------ */

class NotificationComposerScreen extends ConsumerStatefulWidget {
  const NotificationComposerScreen({super.key});
  @override
  ConsumerState<NotificationComposerScreen> createState() => _NotificationComposerScreenState();
}

class _NotificationComposerScreenState extends ConsumerState<NotificationComposerScreen> {
  final _title = TextEditingController(), _body = TextEditingController(), _route = TextEditingController();
  String _audience = 'all'; final Set<String> _tribes = {}; String? _eventId; DateTime? _when; int? _audienceSize; bool _busy = false;

  Future<void> _send({required bool dryRun}) async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(functionsProvider).call('sendTargetedNotification', {'campusId': ref.read(activeCampusIdProvider), 'title': _title.text.trim(), 'body': _body.text.trim(), 'route': _route.text.trim(), 'audience': _audience, 'tribeIds': _tribes.toList(), 'eventId': _eventId, 'scheduledFor': _when?.toUtc().toIso8601String(), 'dryRun': dryRun});
      setState(() => _audienceSize = (r['audienceSize'] as num).toInt());
      if (!dryRun && mounted) showCbSnack(context, 'Queued ${r['queued']} notifications. Delivery respects each student\'s daily cap and preferences.');
    } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final tribes = ref.watch(tribesProvider).value ?? const <Tribe>[];
    final events = ref.watch(upcomingEventsProvider).value ?? const <Event>[];
    final cap = ref.watch(economyProvider).engagementNotificationCapPerDay;
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Notification composer',
      subtitle: 'Engagement messages count toward the $cap-per-day cap. Cancellations bypass it automatically.',
      maxWidth: 760,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _title, maxLength: 80, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: _body, maxLength: 240, maxLines: 3, decoration: const InputDecoration(labelText: 'Body')),
        TextField(controller: _route, decoration: const InputDecoration(labelText: 'Deep link route (optional)', hintText: '/events/abc or /rewards')),
        const SizedBox(height: 12),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'all', label: Text('Everyone')), ButtonSegment(value: 'tribe', label: Text('Tribes')), ButtonSegment(value: 'event_rsvps', label: Text('Event RSVPs')), ButtonSegment(value: 'inactive', label: Text('Inactive 14d'))], selected: {_audience}, onSelectionChanged: (s) => setState(() { _audience = s.first; _audienceSize = null; })),
        const SizedBox(height: 12),
        if (_audience == 'tribe') Wrap(spacing: 8, runSpacing: 8, children: [for (final tr in tribes) CbChip(label: '${tr.emoji} ${tr.name}', selected: _tribes.contains(tr.id), onTap: () => setState(() => _tribes.contains(tr.id) ? _tribes.remove(tr.id) : _tribes.add(tr.id)))]),
        if (_audience == 'event_rsvps') DropdownButtonFormField<String>(initialValue: _eventId, decoration: const InputDecoration(labelText: 'Event'), items: [for (final e in events) DropdownMenuItem(value: e.id, child: Text(e.title, overflow: TextOverflow.ellipsis))], onChanged: (v) => setState(() => _eventId = v)),
        const SizedBox(height: 12),
        Row(children: [OutlinedButton.icon(onPressed: () async { final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60))); if (d == null || !mounted) return; final tm = await showTimePicker(context: context, initialTime: TimeOfDay.now()); if (tm != null) setState(() => _when = DateTime(d.year, d.month, d.day, tm.hour, tm.minute)); }, icon: const Icon(Icons.schedule, size: 18), label: Text(_when == null ? 'Send now' : 'Scheduled ${_when!.toLocal()}')), if (_when != null) TextButton(onPressed: () => setState(() => _when = null), child: const Text('Clear'))]),
        const SizedBox(height: 16),
        CbCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Preview', style: t.labelMedium), const SizedBox(height: 6), Row(children: [Container(width: 36, height: 36, decoration: BoxDecoration(gradient: CbColors.gradient, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.bolt, color: CbColors.dark, size: 20)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_title.text.isEmpty ? 'Title' : _title.text, style: t.titleSmall), Text(_body.text.isEmpty ? 'Body' : _body.text, style: t.bodySmall)]))]), if (_audienceSize != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Audience: $_audienceSize students (before per-user caps and preferences).', style: t.bodyMedium?.copyWith(color: CbColors.limeText)))])),
        const SizedBox(height: 12),
        Row(children: [Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _send(dryRun: true), child: const Text('Validate audience'))), const SizedBox(width: 12), Expanded(child: FilledButton(onPressed: _busy || _title.text.trim().isEmpty || _body.text.trim().isEmpty ? null : () async { if (await confirm(context, title: 'Send to ${_audienceSize ?? '?'} students?', message: 'This is logged in the audit trail.')) _send(dryRun: false); }, child: const Text('Send')))]),
      ]),
    );
  }
}

/* ------------------------------------------------------------------ */
/* Brand quests approval                                               */
/* ------------------------------------------------------------------ */

class AdminQuestsScreen extends ConsumerWidget {
  const AdminQuestsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quests = ref.watch(adminQuestsProvider);
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Brand quests',
      subtitle: 'Approve before students see them. Sponsored labels are mandatory; brands only get aggregates.',
      child: quests.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (list.isEmpty) const CbEmpty(icon: Icons.workspace_premium_outlined, title: 'No quests'),
          for (final q in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: CbCard(borderColor: q.status == 'submitted' ? CbColors.warning : null, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(q.title, style: t.titleMedium)), CbStatusPill(label: q.status, color: q.status == 'live' ? CbColors.success : q.status == 'submitted' ? CbColors.warning : CbColors.textSecondary), const SizedBox(width: 6), CbStatusPill(label: q.financialStatus, color: CbColors.textTertiary)]),
            Text('${q.brandId} · ${q.typeLabel} · +${q.rewardCoins} coins · ${q.stats['joins'] ?? 0} joins · ${q.stats['completions'] ?? 0} completions · value ${Fmt.rupees(q.campaignValue)}', style: t.bodySmall),
            const SizedBox(height: 6),
            Text(q.description, style: t.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (q.status == 'submitted') FilledButton.tonal(onPressed: () => _call(context, ref, 'approveBrandQuest', {'questId': q.id, 'approve': true}, 'Approved.'), child: const Text('Approve')),
              if (q.status == 'submitted') TextButton(style: TextButton.styleFrom(foregroundColor: CbColors.danger), onPressed: () async { final r = await askReason(context, title: 'Return to brand'); if (r != null && context.mounted) _call(context, ref, 'approveBrandQuest', {'questId': q.id, 'approve': false, 'reason': r}, 'Returned to brand.'); }, child: const Text('Reject')),
              if (q.status == 'live') OutlinedButton(onPressed: () => _call(context, ref, 'updateQuestStatus', {'questId': q.id, 'status': 'paused'}, 'Paused.'), child: const Text('Pause')),
              if (q.status == 'paused') OutlinedButton(onPressed: () => _call(context, ref, 'updateQuestStatus', {'questId': q.id, 'status': 'live'}, 'Resumed.'), child: const Text('Resume')),
            ]),
          ]))),
        ]),
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/* Surveys                                                             */
/* ------------------------------------------------------------------ */

class AdminSurveysScreen extends ConsumerWidget {
  const AdminSurveysScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surveys = ref.watch(campusSurveysProvider);
    final dash = ref.watch(campusDashboardProvider).value;
    final campusId = ref.watch(activeCampusIdProvider);
    final t = Theme.of(context).textTheme;
    final survey = dash == null ? null : Map<String, dynamic>.from(dash['survey'] as Map);
    final detail = survey?['npsDetail'] == null ? null : Map<String, dynamic>.from(survey!['npsDetail'] as Map);
    return CbPage(
      title: 'Surveys & NPS',
      actions: [FilledButton.icon(onPressed: () async { final title = await askReason(context, title: 'New pulse survey', hint: 'Title, e.g. "Week 3 pulse check"', confirmLabel: 'Create & notify'); if (title != null && context.mounted) _call(context, ref, 'createSurvey', {'campusId': campusId, 'title': title, 'notify': true}, 'Survey created and queued to students.'); }, icon: const Icon(Icons.add), label: const Text('New survey'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (survey != null) CbStatGrid(children: [
          CbStat(label: 'NPS (latest survey)', value: survey['nps'] == null ? '—' : '${survey['nps']}', hint: 'promoters 9–10 · passives 7–8 · detractors 0–6', icon: Icons.thumb_up_outlined, band: survey['nps'] == null ? null : (survey['nps'] as num) >= 40 ? 'green' : (survey['nps'] as num) >= 20 ? 'yellow' : 'red'),
          CbStat(label: 'Would miss CampusBuzz', value: Fmt.pct(survey['wouldMiss'] as num?), hint: 'yes + strongly yes', icon: Icons.favorite_outline, band: survey['wouldMiss'] == null ? null : (survey['wouldMiss'] as num) >= 50 ? 'green' : (survey['wouldMiss'] as num) >= 20 ? 'yellow' : 'red'),
          CbStat(label: 'Responses', value: '${survey['responses']}', icon: Icons.poll_outlined),
          if (detail != null) CbStat(label: 'Promoters / passives / detractors', value: '${detail['promoters']} / ${detail['passives']} / ${detail['detractors']}', icon: Icons.groups_outlined),
        ]),
        const SizedBox(height: 16),
        surveys.when(loading: () => const CbLoading(), error: (e, _) => CbErrorView(error: e), data: (list) => Column(children: [for (final s in list) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.poll_outlined), title: Text(s.title), subtitle: Text('${s.responses} responses · ${s.status}'), trailing: Wrap(spacing: 4, children: [TextButton(onPressed: () => context.push('/surveys/${s.id}'), child: const Text('Preview')), if (s.status == 'open') TextButton(onPressed: () => ref.read(firestoreProvider).collection(Col.surveys).doc(s.id).update({'status': 'closed'}).catchError((e) { if (context.mounted) showCbError(context, e); }), child: const Text('Close'))]))])),
        const SizedBox(height: 8),
        Text('Surveys are how the pilot measures NPS and "would miss". Keep them short.', style: t.bodySmall),
      ]),
    );
  }
}

/* ------------------------------------------------------------------ */
/* Institutional analytics + exports                                   */
/* ------------------------------------------------------------------ */

final _institutionalProvider = FutureProvider<Map<String, dynamic>>((ref) => ref.read(functionsProvider).call('getInstitutionalAnalytics', {'campusId': ref.watch(activeCampusIdProvider), 'days': 90}));

class InstitutionalScreen extends ConsumerWidget {
  const InstitutionalScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_institutionalProvider);
    final campusId = ref.watch(activeCampusIdProvider);
    final t = Theme.of(context).textTheme;
    Future<void> export(String dataset) async {
      try {
        final r = await ref.read(functionsProvider).call('exportCampusData', {'campusId': campusId, 'dataset': dataset});
        final csv = r['csv'] as String;
        await Clipboard.setData(ClipboardData(text: csv));
        await SharePlus.instance.share(ShareParams(text: csv, subject: 'campusbuzz-$dataset.csv', title: 'campusbuzz-$dataset.csv'));
        if (context.mounted) showCbSnack(context, '${r['rows']} rows exported (also copied to clipboard).');
      } catch (e) { if (context.mounted) showCbError(context, e); }
    }
    return CbPage(
      title: 'Institutional analytics',
      subtitle: 'For student-affairs reporting. Derived from verified participation; can support institutional reporting — CampusBuzz makes no NAAC/NIRF certification claim.',
      actions: [for (final d in const ['events', 'attendance', 'redemptions', 'metrics_daily']) OutlinedButton.icon(onPressed: () => export(d), icon: const Icon(Icons.download, size: 16), label: Text('CSV: $d'))],
      child: data.when(
        loading: () => const CbLoading(),
        error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(_institutionalProvider)),
        data: (a) {
          final trend = (a['trend'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
          final byTribe = (a['participationByTribe'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
          final byClub = (a['clubActivity'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
          final dist = Map<String, dynamic>.from(a['participationDistribution'] as Map);
          final cats = (a['participationByCategory'] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CbStatGrid(children: [CbStat(label: 'Unique participants (90d)', value: '${a['uniqueParticipants']}', icon: Icons.people_outline), CbStat(label: 'Verified check-ins', value: '${a['totalCheckins']}', icon: Icons.verified), CbStat(label: 'Event supply', value: '${a['eventSupply']}', icon: Icons.event), CbStat(label: 'Active clubs', value: '${a['activeClubs']}', icon: Icons.groups_outlined), CbStat(label: 'RSVP → attendance', value: Fmt.pct(a['rsvpToAttendance'] as num?), icon: Icons.trending_up), CbStat(label: 'Repeat attendance', value: Fmt.pct(a['repeatAttendance'] as num?), icon: Icons.repeat)]),
            const SizedBox(height: 16),
            CbLineChart(title: 'Weekly Active Participants', period: 'daily, 90 days', points: trend.map((x) => ((x['wap'] as num?) ?? 0).toDouble()).toList(), labels: trend.map((x) => (x['date'] as String).substring(5)).toList()),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              final charts = [
                CbBarChart(title: 'Participation by Tribe', values: byTribe.map((x) => (x['checkins'] as num).toDouble()).toList(), labels: byTribe.map((x) => x['name'] as String).toList(), color: CbColors.lime),
                CbBarChart(title: 'Club activity', values: byClub.take(10).map((x) => (x['checkins'] as num).toDouble()).toList(), labels: byClub.take(10).map((x) => x['name'] as String).toList()),
                CbBarChart(title: 'Participation distribution', period: 'events per student', values: ['1', '2-3', '4-6', '7+'].map((k) => ((dist[k] as num?) ?? 0).toDouble()).toList(), labels: const ['1', '2–3', '4–6', '7+'], color: CbColors.info),
              ];
              return c.maxWidth > 1000 ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final ch in charts) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: ch))]) : Column(children: [for (final ch in charts) Padding(padding: const EdgeInsets.only(bottom: 12), child: ch)]);
            }),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final c in cats) CbChip(label: '${c['tag']} · ${c['checkins']}')]),
            const SizedBox(height: 8),
            Text(a['note'] as String, style: t.bodySmall),
          ]);
        },
      ),
    );
  }
}

/* ------------------------------------------------------------------ */
/* Configuration                                                       */
/* ------------------------------------------------------------------ */

class CampusConfigScreen extends ConsumerStatefulWidget {
  const CampusConfigScreen({super.key});
  @override
  ConsumerState<CampusConfigScreen> createState() => _CampusConfigScreenState();
}

class _CampusConfigScreenState extends ConsumerState<CampusConfigScreen> {
  final Map<String, TextEditingController> _eco = {};
  final _name = TextEditingController(), _domains = TextEditingController(), _tz = TextEditingController(), _desc = TextEditingController(), _weeklyTarget = TextEditingController(), _minToday = TextEditingController();
  Map<String, bool> _flags = {}; bool _loaded = false, _announce = false, _busy = false;

  void _load(Campus c) {
    if (_loaded) return; _loaded = true;
    _name.text = c.name; _domains.text = c.domains.join(', '); _tz.text = c.timezone; _flags = Map.of(c.featureFlags);
    for (final e in c.economy.toJson().entries) _eco[e.key] = TextEditingController(text: '${e.value}');
    _weeklyTarget.text = '${(c.pilot['targets'] as Map?)?['weeklyEventsTarget'] ?? 8}'; _minToday.text = '${(c.pilot['targets'] as Map?)?['minEventsTodayTomorrow'] ?? 2}';
  }

  Future<void> _save(Campus c) async {
    setState(() => _busy = true);
    try {
      final economy = {for (final e in _eco.entries) e.key: num.tryParse(e.value.text) ?? 0, 'description': _desc.text.trim(), 'announce': _announce};
      final r = await ref.read(functionsProvider).call('updateCampusConfig', {'campusId': c.id, 'name': _name.text.trim(), 'domains': _domains.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(), 'timezone': _tz.text.trim(), 'featureFlags': _flags, 'economy': economy, 'pilot': {'targets': {'weeklyEventsTarget': int.tryParse(_weeklyTarget.text) ?? 8, 'minEventsTodayTomorrow': int.tryParse(_minToday.text) ?? 2}}, 'reason': 'Config update from console'});
      if (mounted) showCbSnack(context, 'Saved. Economy version ${r['economyVersion']}.');
    } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final campus = ref.watch(campusProvider).value;
    final t = Theme.of(context).textTheme;
    if (campus == null) return const CbLoading();
    _load(campus);
    final flagKeys = FeatureFlag.values;
    return CbPage(
      title: 'Configuration',
      subtitle: 'Economy and security changes are versioned and audited. Feature flags and economy are stored separately.',
      maxWidth: 900,
      actions: [FilledButton(onPressed: _busy ? null : () => _save(campus), child: const Text('Save'))],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Campus', style: t.titleLarge),
        const SizedBox(height: 8),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 8),
        TextField(controller: _domains, decoration: const InputDecoration(labelText: 'Verified email domains (comma separated)', helperText: 'Students can only register with these domains.')),
        const SizedBox(height: 8),
        TextField(controller: _tz, decoration: const InputDecoration(labelText: 'Timezone (IANA)', helperText: 'Streak weeks and reminders use this.')),
        const SizedBox(height: 20),
        Text('Economy (v${campus.economy.version})', style: t.titleLarge),
        Text('Changing any value creates a new version. Historical ledger entries are never rewritten.', style: t.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 12, children: [for (final e in _eco.entries) SizedBox(width: 200, child: TextField(controller: e.value, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: e.key)))]),
        const SizedBox(height: 8),
        TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Change description (shown to students if announced)')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Announce this change in-app'), subtitle: const Text('Sends a transactional notice to all members'), value: _announce, onChanged: (v) => setState(() => _announce = v)),
        const SizedBox(height: 20),
        Text('Feed health targets', style: t.titleLarge),
        const SizedBox(height: 8),
        Row(children: [Expanded(child: TextField(controller: _weeklyTarget, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Weekly events target'))), const SizedBox(width: 12), Expanded(child: TextField(controller: _minToday, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Min events today/tomorrow')))]),
        const SizedBox(height: 20),
        Text('Feature flags (campus overrides)', style: t.titleLarge),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final f in flagKeys) FilterChip(label: Text(f.key), selected: _flags[f.key] ?? f.defaultValue, onSelected: (v) => setState(() => _flags[f.key] = v))]),
        const SizedBox(height: 24),
        FilledButton(onPressed: _busy ? null : () => _save(campus), child: Text(_busy ? 'Saving…' : 'Save configuration')),
      ]),
    );
  }
}

/* ------------------------------------------------------------------ */
/* Audit log                                                           */
/* ------------------------------------------------------------------ */

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(auditLogsProvider);
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Audit log',
      subtitle: 'Immutable record of role changes, suspensions, manual check-ins, reward edits, economy config, quest approvals and coin adjustments.',
      child: logs.when(
        loading: () => const CbSkeletonList(height: 60),
        error: (e, _) => CbErrorView(error: e),
        data: (list) => list.isEmpty ? const CbEmpty(icon: Icons.history, title: 'No entries yet') : Column(children: [
          for (final a in list) ExpansionTile(
            tilePadding: EdgeInsets.zero,
            leading: Icon(a.action.startsWith('coins') ? Icons.hexagon_rounded : a.action.startsWith('role') ? Icons.badge_outlined : a.action.startsWith('user') ? Icons.person_off_outlined : a.action.startsWith('checkin') ? Icons.how_to_reg : a.action.startsWith('reward') ? Icons.card_giftcard : Icons.settings_outlined, color: CbColors.limeText),
            title: Text(a.action, style: t.titleSmall),
            subtitle: Text('${a.entityType} ${a.entityId} · by ${a.actorUid.substring(0, a.actorUid.length.clamp(0, 10))} · ${a.at == null ? '' : Fmt.dateTime(a.at!, tz)}', style: t.bodySmall),
            children: [Padding(padding: const EdgeInsets.fromLTRB(0, 0, 0, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [if (a.reason != null) CbKeyValue('Reason', a.reason!), if (a.before != null) CbKeyValue('Before', const JsonEncoder.withIndent('  ').convert(a.before)), if (a.after != null) CbKeyValue('After', const JsonEncoder.withIndent('  ').convert(a.after))]))],
          ),
        ]),
      ),
    );
  }
}
