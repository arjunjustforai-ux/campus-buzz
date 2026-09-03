import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/models/models.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../events/data/event_repository.dart';
import '../../events/presentation/event_card.dart';

enum DateFilter { any, today, tomorrow, week, custom }

/// Search across title / organizer / description keywords / Tribes with date + Tribe + organizer filters.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key, this.initialQuery, this.initialTribe});
  final String? initialQuery, initialTribe;
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  late final TextEditingController _q = TextEditingController(text: widget.initialQuery ?? '');
  DateFilter _date = DateFilter.any; DateTime? _custom; String? _tribe; String? _club; String _query = '';

  @override
  void initState() { super.initState(); _query = widget.initialQuery ?? ''; _tribe = widget.initialTribe; }

  @override
  Widget build(BuildContext context) {
    final searchOn = ref.watch(flagProvider(FeatureFlag.searchEnabled));
    final tz = ref.watch(campusTimezoneProvider);
    final tribes = ref.watch(tribesProvider).value ?? const <Tribe>[];
    final clubs = ref.watch(clubsProvider).value ?? const <Club>[];
    final results = ref.watch(_searchProvider((query: _query, tribe: _tribe, club: _club)));
    return Scaffold(
      appBar: AppBar(title: const Text('Explore')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _q, textInputAction: TextInputAction.search, enabled: searchOn,
            onSubmitted: (v) { setState(() => _query = v.trim()); ref.read(analyticsProvider).track('search_performed', {'source': 'explore'}); },
            onChanged: (v) { if (v.isEmpty) setState(() => _query = ''); },
            decoration: InputDecoration(hintText: 'Search events, clubs, topics', prefixIcon: const Icon(Icons.search), suffixIcon: _q.text.isEmpty ? null : IconButton(onPressed: () { _q.clear(); setState(() => _query = ''); }, icon: const Icon(Icons.close))),
          ),
        ),
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          for (final f in DateFilter.values.where((f) => f != DateFilter.custom)) Padding(padding: const EdgeInsets.only(right: 8), child: CbChip(label: switch (f) { DateFilter.any => 'Any day', DateFilter.today => 'Today', DateFilter.tomorrow => 'Tomorrow', DateFilter.week => 'This week', _ => '' }, selected: _date == f, onTap: () => setState(() => _date = f))),
          Padding(padding: const EdgeInsets.only(right: 8), child: CbChip(label: _custom == null ? 'Pick a date' : Fmt.date(_custom!.toUtc(), tz), icon: Icons.calendar_month, selected: _date == DateFilter.custom, onTap: () async { final d = await showDatePicker(context: context, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 180)), initialDate: _custom ?? DateTime.now()); if (d != null) setState(() { _custom = d; _date = DateFilter.custom; }); })),
          const SizedBox(width: 8),
          for (final tr in tribes) Padding(padding: const EdgeInsets.only(right: 8), child: CbChip(label: '${tr.emoji} ${tr.name}'.trim(), selected: _tribe == tr.id, onTap: () => setState(() => _tribe = _tribe == tr.id ? null : tr.id))),
        ])),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            Expanded(child: DropdownButtonFormField<String?>(initialValue: _club, decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)), items: [const DropdownMenuItem(value: null, child: Text('Any organizer')), for (final c in clubs) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))], onChanged: (v) => setState(() => _club = v))),
            if (_tribe != null || _club != null || _date != DateFilter.any || _query.isNotEmpty) TextButton(onPressed: () { _q.clear(); setState(() { _query = ''; _tribe = null; _club = null; _date = DateFilter.any; _custom = null; }); }, child: const Text('Reset')),
          ]),
        ),
        Expanded(
          child: results.when(
            loading: () => const CbSkeletonList(),
            error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(_searchProvider((query: _query, tribe: _tribe, club: _club)))),
            data: (list) {
              final filtered = list.where((e) => _matchesDate(e, tz)).toList();
              if (filtered.isEmpty) return CbEmpty(icon: Icons.search_off, title: 'No events match', message: 'Try fewer filters, another day, or a different Tribe.', actionLabel: 'Reset filters', action: () { _q.clear(); setState(() { _query = ''; _tribe = null; _club = null; _date = DateFilter.any; }); });
              return ListView.separated(padding: const EdgeInsets.all(16), itemCount: filtered.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (_, i) => EventCard(event: filtered[i], source: 'search', compact: true));
            },
          ),
        ),
      ]),
    );
  }

  bool _matchesDate(Event e, String tz) {
    if (_date == DateFilter.any) return true;
    final local = Fmt.inCampus(e.startAt, tz);
    final now = Fmt.inCampus(DateTime.now().toUtc(), tz);
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    return switch (_date) {
      DateFilter.today => day == today,
      DateFilter.tomorrow => day == today.add(const Duration(days: 1)),
      DateFilter.week => !day.isBefore(today) && day.isBefore(today.add(const Duration(days: 7))),
      DateFilter.custom => _custom != null && day == DateTime(_custom!.year, _custom!.month, _custom!.day),
      _ => true,
    };
  }
}

typedef _SearchArgs = ({String query, String? tribe, String? club});

final _searchProvider = StreamProvider.family<List<Event>, _SearchArgs>((ref, a) {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return Stream.value(const []);
  final db = ref.watch(firestoreProvider);
  Query<Map<String, dynamic>> q = db.collection(Col.events).where('status', isEqualTo: 'published').where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime.now().toUtc().subtract(const Duration(hours: 3))));
  final token = a.query.toLowerCase().trim().split(RegExp(r'\s+')).where((w) => w.length >= 2).firstOrNull;
  if (token != null) {
    q = q.where('searchTokens', arrayContains: token);
  } else if (a.tribe != null) {
    q = q.where('tribeIds', arrayContains: a.tribe);
  } else {
    q = q.where('participatingCampusIds', arrayContains: campusId);
  }
  if (a.club != null) q = q.where('clubId', isEqualTo: a.club);
  return q.orderBy('startAt').limit(80).snapshots().map((s) => s.docs.map(Event.fromDoc).where((e) => e.participatingCampusIds.contains(campusId) && (a.tribe == null || e.tribeIds.contains(a.tribe)) && _fullMatch(e, a.query)).toList());
});

bool _fullMatch(Event e, String query) {
  final words = query.toLowerCase().trim().split(RegExp(r'\s+')).where((w) => w.length >= 2);
  final hay = '${e.title} ${e.clubName} ${e.description} ${e.tags.join(' ')}'.toLowerCase();
  return words.every(hay.contains);
}
