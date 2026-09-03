import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

/// Clubs the current organizer manages (campus admins see all).
final myClubsProvider = Provider<List<Club>>((ref) {
  final clubs = ref.watch(clubsProvider).value ?? const <Club>[];
  final m = ref.watch(membershipProvider).value;
  if (ref.watch(rolesProvider).contains(Role.campusAdmin)) return clubs;
  return clubs.where((c) => m?.clubIds.contains(c.id) ?? false).toList();
});

final clubEventsProvider = StreamProvider.family<List<Event>, String>((ref, clubId) => ref.watch(firestoreProvider).collection(Col.events).where('clubId', isEqualTo: clubId).orderBy('startAt', descending: true).limit(60).snapshots().map((s) => s.docs.map(Event.fromDoc).toList()));

final organizerEventsProvider = StreamProvider<List<Event>>((ref) {
  final clubs = ref.watch(myClubsProvider);
  if (clubs.isEmpty) return Stream.value(const []);
  final ids = clubs.map((c) => c.id).take(10).toList();
  return ref.watch(firestoreProvider).collection(Col.events).where('clubId', whereIn: ids).orderBy('startAt', descending: true).limit(100).snapshots().map((s) => s.docs.map(Event.fromDoc).toList());
});

final eventRsvpsProvider = StreamProvider.family<List<Rsvp>, String>((ref, eventId) => ref.watch(firestoreProvider).collection(Col.rsvps).where('eventId', isEqualTo: eventId).where('status', whereIn: ['confirmed', 'waitlisted']).limit(500).snapshots().map((s) => s.docs.map(Rsvp.fromDoc).toList()));
final eventCheckinsProvider = StreamProvider.family<List<Checkin>, String>((ref, eventId) => ref.watch(firestoreProvider).collection(Col.checkins).where('eventId', isEqualTo: eventId).limit(1000).snapshots().map((s) => s.docs.map(Checkin.fromDoc).toList()));

class OrganizerDashboardScreen extends ConsumerWidget {
  const OrganizerDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(organizerEventsProvider);
    final clubs = ref.watch(myClubsProvider);
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Overview',
      subtitle: clubs.map((c) => c.name).join(' · '),
      actions: [FilledButton.icon(onPressed: () => context.go('/organizer/events/new'), icon: const Icon(Icons.add), label: const Text('Create event'))],
      child: events.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) {
          if (clubs.isEmpty) return const CbEmpty(icon: Icons.groups_outlined, title: 'No club linked yet', message: 'Campus operations links your account to a club when they approve organizer access.');
          final now = DateTime.now().toUtc();
          final upcoming = list.where((e) => e.status == 'published' && e.endAt.isAfter(now)).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));
          final past = list.where((e) => e.isCompleted).toList();
          final upRsvps = upcoming.fold<int>(0, (s, e) => s + e.stats.rsvpCount);
          final pastRsvps = past.fold<int>(0, (s, e) => s + e.stats.rsvpCount), pastCheckins = past.fold<int>(0, (s, e) => s + e.stats.checkinCount);
          final live = upcoming.where((e) => e.checkinActive).toList();
          final feedback = past.where((e) => e.stats.feedbackCount > 0).toList();
          final warnings = <String>[
            if (upcoming.isEmpty) 'No upcoming events — your club is invisible in the feed right now.',
            if (upcoming.any((e) => e.startAt.difference(now).inHours < 24 && e.stats.rsvpCount < 5)) 'An event starts within 24h with fewer than 5 RSVPs.',
            if (past.any((e) => e.stats.rsvpCount > 0 && e.stats.conversion < 25)) 'Some past events converted under 25% RSVP→attendance. Check reminders and timing.',
          ];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (live.isNotEmpty) for (final e in live) Padding(padding: const EdgeInsets.only(bottom: 12), child: CbCard(gradient: true, onTap: () => context.go('/organizer/events/${e.id}/live'), child: Row(children: [const Icon(Icons.qr_code, color: CbColors.limeText, size: 28), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Check-in live · ${e.title}', style: t.titleMedium), Text('${e.stats.checkinCount} checked in of ${e.stats.rsvpCount} RSVPs', style: t.bodySmall)])), const Icon(Icons.chevron_right)]))),
            CbStatGrid(children: [
              CbStat(label: 'Upcoming events', value: '${upcoming.length}', icon: Icons.event),
              CbStat(label: 'Upcoming RSVPs', value: '$upRsvps', icon: Icons.how_to_reg),
              CbStat(label: 'Verified attendance', value: '$pastCheckins', hint: 'Across ${past.length} past events', icon: Icons.verified),
              CbStat(label: 'RSVP → attendance', value: Fmt.pct(pastRsvps == 0 ? null : pastCheckins / pastRsvps * 100), icon: Icons.trending_up, band: pastRsvps == 0 ? null : (pastCheckins / pastRsvps * 100 >= 40 ? 'green' : pastCheckins / pastRsvps * 100 >= 25 ? 'yellow' : 'red')),
              CbStat(label: 'Avg rating', value: feedback.isEmpty ? '—' : (feedback.fold<double>(0, (s, e) => s + e.stats.ratingAvg) / feedback.length).toStringAsFixed(1), icon: Icons.star_outline),
            ]),
            if (warnings.isNotEmpty) ...[const SizedBox(height: 16), for (final w in warnings) Padding(padding: const EdgeInsets.only(bottom: 8), child: CbCard(padding: const EdgeInsets.all(12), borderColor: CbColors.warning, child: Row(children: [const Icon(Icons.warning_amber_rounded, color: CbColors.warning), const SizedBox(width: 10), Expanded(child: Text(w, style: t.bodyMedium))])))],
            const SizedBox(height: 20),
            Text('Upcoming', style: t.titleLarge),
            const SizedBox(height: 8),
            if (upcoming.isEmpty) const CbEmpty(icon: Icons.event_busy, title: 'Nothing scheduled', message: 'Posting takes about 60 seconds.'),
            for (final e in upcoming.take(8)) _EventRow(event: e, tz: tz),
            const SizedBox(height: 20),
            Text('Recent feedback', style: t.titleLarge),
            const SizedBox(height: 8),
            if (feedback.isEmpty) Text('Ratings show up after you close an event.', style: t.bodyMedium),
            for (final e in feedback.take(4)) ListTile(contentPadding: EdgeInsets.zero, title: Text(e.title), subtitle: Text('${e.stats.feedbackCount} reviews'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.star, color: CbColors.warning, size: 16), Text(' ${e.stats.ratingAvg.toStringAsFixed(1)}', style: t.titleMedium)]), onTap: () => context.go('/organizer/events/${e.id}/analytics')),
          ]);
        },
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.tz});
  final Event event; final String tz;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = switch (event.status) { 'published' => CbColors.success, 'draft' => CbColors.textTertiary, 'cancelled' => CbColors.danger, _ => CbColors.info };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CbCard(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), onTap: () => context.go('/organizer/events/${event.id}'), child: Row(children: [
        SizedBox(width: 64, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(Fmt.monthDay(event.startAt, tz), style: t.titleMedium), Text(Fmt.time(event.startAt, tz), style: t.labelSmall)])),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(event.title, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis), Text('${event.stats.rsvpCount} RSVPs · ${event.stats.checkinCount} checked in${event.reviewStatus == 'pending_review' ? ' · awaiting ops review' : event.reviewStatus == 'flagged' ? ' · flagged' : ''}', style: t.bodySmall)])),
        CbStatusPill(label: event.status, color: color),
      ])),
    );
  }
}

class OrganizerEventsScreen extends ConsumerWidget {
  const OrganizerEventsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(organizerEventsProvider);
    final tz = ref.watch(campusTimezoneProvider);
    return CbPage(
      title: 'Events',
      actions: [FilledButton.icon(onPressed: () => context.go('/organizer/events/new'), icon: const Icon(Icons.add), label: const Text('Create'))],
      child: events.when(loading: () => const CbSkeletonList(), error: (e, _) => CbErrorView(error: e), data: (list) => list.isEmpty ? const CbEmpty(icon: Icons.event, title: 'No events yet') : Column(children: [for (final e in list) _EventRow(event: e, tz: tz)])),
    );
  }
}

/// ~60-second event creation. Required: title, description, date/time, location, capacity, Tribes.
class EventFormScreen extends ConsumerStatefulWidget {
  const EventFormScreen({super.key, this.eventId});
  final String? eventId;
  @override
  ConsumerState<EventFormScreen> createState() => _EventFormScreenState();
}

class _EventFormScreenState extends ConsumerState<EventFormScreen> {
  final _title = TextEditingController(), _desc = TextEditingController(), _loc = TextEditingController(), _addr = TextEditingController(), _cap = TextEditingController(text: '100'), _contact = TextEditingController(), _tags = TextEditingController();
  String? _clubId; DateTime? _start; DateTime? _end; final Set<String> _tribes = {}; final Set<String> _campuses = {}; bool _waitlist = true, _cert = true, _busy = false, _loaded = false; String? _posterUrl; double? _lat, _lng;

  void _load(Event e) {
    if (_loaded) return; _loaded = true;
    _title.text = e.title; _desc.text = e.description; _loc.text = e.location.name; _addr.text = e.location.address; _cap.text = '${e.capacity}'; _contact.text = e.contact; _tags.text = e.tags.join(', ');
    _clubId = e.clubId; _start = e.startAt.toLocal(); _end = e.endAt.toLocal(); _tribes.addAll(e.tribeIds); _campuses.addAll(e.participatingCampusIds); _waitlist = e.waitlistEnabled; _cert = e.certificateEnabled; _posterUrl = e.posterUrl; _lat = e.location.lat; _lng = e.location.lng;
  }

  Future<void> _pickDateTime(bool start) async {
    final base = start ? (_start ?? DateTime.now().add(const Duration(days: 1))) : (_end ?? (_start ?? DateTime.now()).add(const Duration(hours: 2)));
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null || !mounted) return;
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (tm == null) return;
    final v = DateTime(d.year, d.month, d.day, tm.hour, tm.minute);
    setState(() { if (start) { _start = v; _end ??= v.add(const Duration(hours: 2)); if (_end!.isBefore(v)) _end = v.add(const Duration(hours: 2)); } else { _end = v; } });
  }

  Future<void> _pickPoster(String campusId) async {
    if (_clubId == null) { showCbSnack(context, 'Pick a club first.', error: true); return; }
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final r = FirebaseStorage.instance.ref('posters/$campusId/$_clubId/${DateTime.now().millisecondsSinceEpoch}.jpg');
      await r.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await r.getDownloadURL();
      setState(() => _posterUrl = url);
    } catch (e) { if (mounted) showCbError(context, e); }
  }

  Future<void> _submit({required bool publish}) async {
    if (_title.text.trim().isEmpty || _desc.text.trim().isEmpty || _loc.text.trim().isEmpty || _start == null || _end == null || _clubId == null || _tribes.isEmpty) { showCbSnack(context, 'Fill title, description, when, where, club and at least one Tribe.', error: true); return; }
    setState(() => _busy = true);
    try {
      final campusId = ref.read(activeCampusIdProvider);
      final data = {
        'campusId': campusId, 'clubId': _clubId, 'title': _title.text.trim(), 'description': _desc.text.trim(), 'posterUrl': _posterUrl, 'startAt': _start!.toUtc().toIso8601String(), 'endAt': _end!.toUtc().toIso8601String(),
        'location': {'name': _loc.text.trim(), 'address': _addr.text.trim(), 'lat': _lat, 'lng': _lng}, 'capacity': int.tryParse(_cap.text) ?? 0, 'waitlistEnabled': _waitlist, 'tribeIds': _tribes.toList(), 'tags': _tags.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        'participatingCampusIds': _campuses.toList(), 'contact': _contact.text.trim(), 'certificateEnabled': _cert, 'publish': publish,
      };
      if (widget.eventId == null) {
        final r = await ref.read(functionsProvider).call('createEvent', data);
        if (mounted) { showCbSnack(context, publish ? 'Published. It\'s live in the feed.' : 'Draft saved.'); context.go('/organizer/events/${r['eventId']}'); }
      } else {
        final r = await ref.read(functionsProvider).call('updateEvent', {...data, 'eventId': widget.eventId});
        if (mounted) { showCbSnack(context, r['notifiedRsvps'] == true ? 'Saved. RSVPs were notified about the change.' : 'Saved.'); context.go('/organizer/events/${widget.eventId}'); }
      }
    } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final clubs = ref.watch(myClubsProvider);
    final tribes = ref.watch(tribesProvider).value ?? const <Tribe>[];
    final campusId = ref.watch(activeCampusIdProvider) ?? '';
    final intercampus = ref.watch(flagProvider(FeatureFlag.intercampusEventsEnabled));
    final tz = ref.watch(campusTimezoneProvider);
    final existing = widget.eventId == null ? null : ref.watch(eventProvider(widget.eventId!)).value;
    if (existing != null) _load(existing);
    if (_campuses.isEmpty && campusId.isNotEmpty) _campuses.add(campusId);
    _clubId ??= clubs.length == 1 ? clubs.first.id : null;
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: widget.eventId == null ? 'Create event' : 'Edit event',
      subtitle: 'Sixty seconds, then it\'s in the feed. Campus ops reviews after publication.',
      maxWidth: 760,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DropdownButtonFormField<String>(initialValue: _clubId, decoration: const InputDecoration(labelText: 'Organizer / club'), items: [for (final c in clubs) DropdownMenuItem(value: c.id, child: Text(c.name))], onChanged: widget.eventId != null ? null : (v) => setState(() => _clubId = v)),
        const SizedBox(height: 12),
        TextField(controller: _title, maxLength: 120, decoration: const InputDecoration(labelText: 'Title')),
        TextField(controller: _desc, maxLines: 5, maxLength: 5000, decoration: const InputDecoration(labelText: 'Description')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: () => _pickDateTime(true), icon: const Icon(Icons.calendar_today, size: 18), label: Text(_start == null ? 'Start' : Fmt.dateTime(_start!.toUtc(), tz)))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: () => _pickDateTime(false), icon: const Icon(Icons.schedule, size: 18), label: Text(_end == null ? 'End' : Fmt.dateTime(_end!.toUtc(), tz)))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: _loc, decoration: const InputDecoration(labelText: 'Venue')),
        const SizedBox(height: 8),
        TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Address / directions (optional)')),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Lat (optional)'), controller: TextEditingController(text: _lat?.toString() ?? ''), onChanged: (v) => _lat = double.tryParse(v))),
          const SizedBox(width: 8),
          Expanded(child: TextField(keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Lng (optional)'), controller: TextEditingController(text: _lng?.toString() ?? ''), onChanged: (v) => _lng = double.tryParse(v))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _cap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacity (0 = open)'))),
          const SizedBox(width: 12),
          Expanded(child: SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Waitlist'), value: _waitlist, onChanged: (v) => setState(() => _waitlist = v))),
        ]),
        const SizedBox(height: 8),
        Text('Tribes', style: t.titleSmall),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final tr in tribes) CbChip(label: '${tr.emoji} ${tr.name}'.trim(), selected: _tribes.contains(tr.id), onTap: () => setState(() => _tribes.contains(tr.id) ? _tribes.remove(tr.id) : _tribes.add(tr.id)))]),
        const SizedBox(height: 12),
        TextField(controller: _tags, decoration: const InputDecoration(labelText: 'Tags (comma separated)', hintText: 'workshop, finance, competition')),
        const SizedBox(height: 8),
        TextField(controller: _contact, decoration: const InputDecoration(labelText: 'Contact (optional)')),
        const SizedBox(height: 8),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Issue participation certificates'), value: _cert, onChanged: (v) => setState(() => _cert = v)),
        if (intercampus) ...[
          const SizedBox(height: 8),
          Text('Participating campuses', style: t.titleSmall),
          _CampusPicker(selected: _campuses, host: campusId, onChanged: () => setState(() {})),
        ],
        const SizedBox(height: 12),
        Row(children: [
          OutlinedButton.icon(onPressed: () => _pickPoster(campusId), icon: const Icon(Icons.image_outlined), label: Text(_posterUrl == null ? 'Add poster' : 'Replace poster')),
          if (_posterUrl != null) ...[const SizedBox(width: 8), TextButton(onPressed: () => setState(() => _posterUrl = null), child: const Text('Remove'))],
        ]),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _submit(publish: false), child: const Text('Save draft'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: _busy ? null : () => _submit(publish: true), child: Text(_busy ? 'Saving…' : 'Publish'))),
        ]),
      ]),
    );
  }
}

class _CampusPicker extends ConsumerWidget {
  const _CampusPicker({required this.selected, required this.host, required this.onChanged});
  final Set<String> selected; final String host; final VoidCallback onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campuses = ref.watch(_allCampusesProvider).value ?? const <Campus>[];
    return Wrap(spacing: 8, runSpacing: 8, children: [for (final c in campuses) CbChip(label: c.shortName, selected: selected.contains(c.id), onTap: c.id == host ? null : () { selected.contains(c.id) ? selected.remove(c.id) : selected.add(c.id); onChanged(); })]);
  }
}

final _allCampusesProvider = StreamProvider<List<Campus>>((ref) => ref.watch(firestoreProvider).collection(Col.campuses).where('status', isEqualTo: 'active').snapshots().map((s) => s.docs.map(Campus.fromDoc).toList()));

class EventManageScreen extends ConsumerWidget {
  const EventManageScreen({super.key, required this.eventId});
  final String eventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventProvider(eventId));
    final rsvps = ref.watch(eventRsvpsProvider(eventId)).value ?? const <Rsvp>[];
    final checkins = ref.watch(eventCheckinsProvider(eventId)).value ?? const <Checkin>[];
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    Future<void> call(String fn, Map<String, dynamic> data, String ok) async { try { await ref.read(functionsProvider).call(fn, data); if (context.mounted) showCbSnack(context, ok); } catch (e) { if (context.mounted) showCbError(context, e); } }
    return event.when(
      loading: () => const CbLoading(),
      error: (e, _) => CbErrorView(error: e),
      data: (e) {
        if (e == null) return const CbEmpty(title: 'Event not found');
        final checkedIn = {for (final c in checkins) c.uid};
        final canOpen = DateTime.now().toUtc().isAfter(e.checkinOpensAt ?? e.startAt) && DateTime.now().toUtc().isBefore(e.checkinClosesAt ?? e.endAt);
        return CbPage(
          title: e.title,
          subtitle: '${Fmt.dateTime(e.startAt, tz)} · ${e.location.name} · ${e.status}',
          actions: [
            if (e.status == 'draft' || e.status == 'published') OutlinedButton.icon(onPressed: () => context.go('/organizer/events/$eventId/edit'), icon: const Icon(Icons.edit, size: 18), label: const Text('Edit')),
            if (e.status == 'published') FilledButton.icon(onPressed: () => context.go('/organizer/events/$eventId/live'), icon: const Icon(Icons.qr_code), label: Text(e.checkinActive ? 'Live QR' : canOpen ? 'Start check-in' : 'Live mode')),
            OutlinedButton.icon(onPressed: () => context.go('/organizer/events/$eventId/analytics'), icon: const Icon(Icons.insights, size: 18), label: const Text('Analytics')),
            if (e.status == 'published') OutlinedButton(onPressed: () async { if (await confirm(context, title: 'Close this event?', message: 'Finalises attendance, triggers feedback prompts and the organizer bonus (if ≥10 verified attendees).')) call('closeEvent', {'eventId': eventId}, 'Event closed.'); }, child: const Text('Close event')),
            if (e.status == 'published' || e.status == 'draft') TextButton(style: TextButton.styleFrom(foregroundColor: CbColors.danger), onPressed: () async { final r = await askReason(context, title: 'Cancel event', hint: 'Students who RSVP\'d will be notified with this reason.', confirmLabel: 'Cancel event'); if (r != null) call('cancelEvent', {'eventId': eventId, 'reason': r}, 'Cancelled. RSVPs notified.'); }, child: const Text('Cancel event')),
          ],
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (e.reviewStatus == 'flagged') Padding(padding: const EdgeInsets.only(bottom: 12), child: CbCard(borderColor: CbColors.warning, padding: const EdgeInsets.all(12), child: Row(children: [const Icon(Icons.flag, color: CbColors.warning), const SizedBox(width: 10), Expanded(child: Text('This event was reported and is under campus ops review. It stays live unless they unpublish it.', style: t.bodyMedium))]))),
            CbStatGrid(children: [
              CbStat(label: 'RSVPs', value: '${e.stats.rsvpCount}', hint: e.capacity > 0 ? 'of ${e.capacity} capacity' : 'open capacity', icon: Icons.how_to_reg),
              CbStat(label: 'Waitlist', value: '${e.stats.waitlistCount}', icon: Icons.hourglass_empty),
              CbStat(label: 'Checked in', value: '${e.stats.checkinCount}', hint: '${e.stats.manualCheckinCount} manual', icon: Icons.verified),
              CbStat(label: 'Conversion', value: Fmt.pct(e.stats.rsvpCount == 0 ? null : e.stats.conversion), icon: Icons.trending_up),
            ]),
            const SizedBox(height: 20),
            Text('RSVP list (${rsvps.length})', style: t.titleLarge),
            const SizedBox(height: 8),
            if (rsvps.isEmpty) Text('No RSVPs yet.', style: t.bodyMedium),
            for (final r in rsvps.take(200)) _AttendeeRow(uid: r.uid, subtitle: '${r.status}${checkedIn.contains(r.uid) ? ' · checked in' : ''}', checkedIn: checkedIn.contains(r.uid), onManual: e.status == 'cancelled' || checkedIn.contains(r.uid) ? null : () async { final reason = await askReason(context, title: 'Manual check-in', hint: 'Why manual? (camera broken, QR not loading…)', required: false); if (reason == null) return; call('manualCheckIn', {'eventId': eventId, 'uid': r.uid, 'reason': reason.isEmpty ? 'Manual fallback' : reason}, 'Checked in manually (audited).'); }),
          ]),
        );
      },
    );
  }
}

class _AttendeeRow extends ConsumerWidget {
  const _AttendeeRow({required this.uid, required this.subtitle, required this.checkedIn, this.onManual});
  final String uid, subtitle; final bool checkedIn; final VoidCallback? onManual;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(_nameProvider(uid)).value ?? '…';
    return ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: Icon(checkedIn ? Icons.verified : Icons.person_outline, color: checkedIn ? CbColors.success : CbColors.textTertiary), title: Text(name), subtitle: Text(subtitle), trailing: onManual == null ? null : TextButton(onPressed: onManual, child: const Text('Manual check-in')));
  }
}

final _nameProvider = FutureProvider.family<String, String>((ref, uid) async {
  final campusId = ref.watch(activeCampusIdProvider);
  if (campusId == null) return uid;
  final s = await ref.watch(firestoreProvider).collection(Col.memberships).doc(Ids.membership(campusId, uid)).get();
  return s.data()?['displayName'] as String? ?? uid.substring(0, 8);
});

/// Live event mode: giant rotating QR, counts, QR health, manual check-in with attendee lookup.
class LiveEventScreen extends ConsumerStatefulWidget {
  const LiveEventScreen({super.key, required this.eventId});
  final String eventId;
  @override
  ConsumerState<LiveEventScreen> createState() => _LiveEventScreenState();
}

class _LiveEventScreenState extends ConsumerState<LiveEventScreen> {
  Timer? _timer; String? _token; int _expiresAtMs = 0; String? _error; bool _starting = false; int _failures = 0;
  final _search = TextEditingController(); List<Map<String, dynamic>> _results = const [];

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _start() async {
    setState(() { _starting = true; _error = null; });
    try { await ref.read(functionsProvider).call('startEventCheckin', {'eventId': widget.eventId}); await _refresh(); _timer ??= Timer.periodic(const Duration(seconds: 5), (_) { if (DateTime.now().millisecondsSinceEpoch > _expiresAtMs - 6000) _refresh(); else setState(() {}); }); } catch (e) { setState(() => _error = e.toString()); if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _starting = false); }
  }

  Future<void> _refresh() async {
    try { final r = await ref.read(functionsProvider).call('issueEventQrToken', {'eventId': widget.eventId}); if (!mounted) return; setState(() { _token = r['token'] as String; _expiresAtMs = (r['expiresAtMs'] as num).toInt(); _failures = 0; _error = null; }); } catch (e) { _failures++; if (mounted) setState(() => _error = 'QR refresh failed ($_failures). Check connectivity; manual check-in still works.'); }
  }

  Future<void> _stop() async { _timer?.cancel(); _timer = null; try { await ref.read(functionsProvider).call('stopEventCheckin', {'eventId': widget.eventId}); setState(() => _token = null); } catch (e) { if (mounted) showCbError(context, e); } }

  Future<void> _find() async { try { final r = await ref.read(functionsProvider).call('searchAttendees', {'eventId': widget.eventId, 'query': _search.text.trim()}); setState(() => _results = ((r['results'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList()); } catch (e) { if (mounted) showCbError(context, e); } }

  @override
  Widget build(BuildContext context) {
    final event = ref.watch(eventProvider(widget.eventId)).value;
    final t = Theme.of(context).textTheme;
    if (event == null) return const CbLoading();
    if (event.checkinActive && _timer == null && _token == null && !_starting) WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    final secondsLeft = ((_expiresAtMs - DateTime.now().millisecondsSinceEpoch) / 1000).clamp(0, 30).round();
    final healthy = _token != null && _failures == 0;
    return CbPage(
      title: 'Live · ${event.title}',
      subtitle: 'Students scan this. It rotates every 30 seconds.',
      actions: [
        if (event.checkinActive) OutlinedButton(onPressed: _stop, child: const Text('Stop check-in')),
        OutlinedButton.icon(onPressed: () => context.go('/organizer/events/${widget.eventId}'), icon: const Icon(Icons.list, size: 18), label: const Text('RSVP list')),
      ],
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 800;
        final qr = Column(children: [
          Container(
            padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
            child: _token == null
                ? SizedBox(width: 320, height: 320, child: Center(child: _starting ? const CircularProgressIndicator() : FilledButton.icon(onPressed: _start, icon: const Icon(Icons.play_arrow), label: const Text('Start check-in'))))
                : QrImageView(data: _token!, size: 320, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
          ),
          const SizedBox(height: 12),
          if (_token != null) Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(healthy ? Icons.check_circle : Icons.warning_amber_rounded, color: healthy ? CbColors.success : CbColors.warning, size: 18), const SizedBox(width: 6), Text(healthy ? 'QR healthy · refreshes in ${secondsLeft}s' : (_error ?? 'Refreshing…'), style: t.labelMedium)]),
          if (_token != null) TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: _token!)); showCbSnack(context, 'Token copied (for web/dev testing)'); }, icon: const Icon(Icons.copy, size: 14), label: const Text('Copy token')),
          if (_error != null && _token == null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: t.bodySmall?.copyWith(color: CbColors.danger))),
        ]);
        final side = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CbStatGrid(minTileWidth: 140, children: [
            CbStat(label: 'Checked in', value: '${event.stats.checkinCount}', icon: Icons.verified, color: CbColors.limeText),
            CbStat(label: 'RSVPs', value: '${event.stats.rsvpCount}', icon: Icons.how_to_reg),
            CbStat(label: 'Capacity', value: event.capacity == 0 ? 'Open' : '${event.capacity}', icon: Icons.people_outline),
          ]),
          const SizedBox(height: 16),
          Text('Manual check-in (fallback)', style: t.titleLarge),
          const SizedBox(height: 4),
          Text('For phones that won\'t scan. Every manual check-in is audited and pays the same coins once.', style: t.bodySmall),
          const SizedBox(height: 8),
          TextField(controller: _search, onSubmitted: (_) => _find(), decoration: InputDecoration(hintText: 'Search attendee by name', prefixIcon: const Icon(Icons.search), suffixIcon: IconButton(onPressed: _find, icon: const Icon(Icons.arrow_forward)))),
          for (final r in _results)
            ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: Icon(r['checkedIn'] == true ? Icons.verified : r['rsvped'] == true ? Icons.how_to_reg : Icons.person_outline, color: r['checkedIn'] == true ? CbColors.success : CbColors.textTertiary), title: Text(r['displayName'] as String? ?? ''), subtitle: Text(r['checkedIn'] == true ? 'Already checked in' : r['rsvped'] == true ? 'RSVP\'d' : 'No RSVP'), trailing: r['checkedIn'] == true ? null : TextButton(onPressed: () async { final reason = await askReason(context, title: 'Manual check-in', hint: 'Reason (optional)', required: false); if (reason == null) return; try { final res = await ref.read(functionsProvider).call('manualCheckIn', {'eventId': widget.eventId, 'uid': r['uid'], 'reason': reason.isEmpty ? 'Manual fallback' : reason}); if (context.mounted) showCbSnack(context, res['alreadyCheckedIn'] == true ? 'Already checked in.' : 'Checked in · +${res['coins']} coins.'); await _find(); } catch (e) { if (context.mounted) showCbError(context, e); } }, child: const Text('Check in'))),
        ]);
        return wide ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: qr), const SizedBox(width: 24), Expanded(child: side)]) : Column(children: [qr, const SizedBox(height: 24), side]);
      }),
    );
  }
}

class EventAnalyticsScreen extends ConsumerWidget {
  const EventAnalyticsScreen({super.key, required this.eventId});
  final String eventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_eventAnalyticsProvider(eventId));
    final event = ref.watch(eventProvider(eventId)).value;
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Analytics · ${event?.title ?? ''}',
      actions: [OutlinedButton.icon(onPressed: () => ref.invalidate(_eventAnalyticsProvider(eventId)), icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh'))],
      child: data.when(
        loading: () => const CbLoading(message: 'Crunching attendance…'),
        error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(_eventAnalyticsProvider(eventId))),
        data: (a) {
          final tribes = (a['tribeBreakdown'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final dist = Map<String, dynamic>.from(a['rating']['distribution'] as Map? ?? {});
          final fb = (a['feedback'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final themes = (a['themes'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final timeline = (a['checkinTimeline'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            CbStatGrid(children: [
              CbStat(label: 'Impressions', value: '${a['impressions']}', icon: Icons.visibility_outlined),
              CbStat(label: 'Unique opens', value: '${a['uniqueOpens']}', icon: Icons.touch_app_outlined),
              CbStat(label: 'RSVPs', value: '${a['rsvps']}', hint: 'Discovery conversion ${Fmt.pct(a['conversion']['discovery'] as num?)}', icon: Icons.how_to_reg),
              CbStat(label: 'Verified check-ins', value: '${a['checkins']}', hint: '${a['manualCheckins']} manual', icon: Icons.verified),
              CbStat(label: 'RSVP → attendance', value: Fmt.pct(a['conversion']['attendance'] as num?), icon: Icons.trending_up, band: (a['rsvps'] as num) == 0 ? null : ((a['conversion']['attendance'] as num) >= 40 ? 'green' : (a['conversion']['attendance'] as num) >= 25 ? 'yellow' : 'red')),
              CbStat(label: 'Repeat attendees', value: Fmt.pct(a['repeatAttendeeRate'] as num?), hint: 'Attended another of your events', icon: Icons.repeat),
              CbStat(label: 'Rating', value: (a['rating']['count'] as num) == 0 ? '—' : '${(a['rating']['avg'] as num).toStringAsFixed(1)} ★', hint: '${a['rating']['count']} reviews', icon: Icons.star_outline),
            ]),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, c) {
              final charts = [
                CbBarChart(title: 'Tribe breakdown', period: 'RSVPs vs check-ins', values: tribes.map((x) => (x['rsvps'] as num).toDouble()).toList(), secondary: tribes.map((x) => (x['checkins'] as num).toDouble()).toList(), labels: tribes.map((x) => x['name'] as String).toList(), primaryLabel: 'RSVPs', secondaryLabel: 'Checked in'),
                CbBarChart(title: 'Rating distribution', values: [for (var i = 1; i <= 5; i++) ((dist['$i'] as num?) ?? 0).toDouble()], labels: const ['1★', '2★', '3★', '4★', '5★'], color: CbColors.warning),
                CbLineChart(title: 'Check-in timeline', period: 'minutes from first scan', points: timeline.map((x) => (x['count'] as num).toDouble()).toList(), labels: timeline.map((x) => '${x['minute']}m').toList()),
              ];
              return c.maxWidth > 900 ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final ch in charts) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: ch))]) : Column(children: [for (final ch in charts) Padding(padding: const EdgeInsets.only(bottom: 12), child: ch)]);
            }),
            const SizedBox(height: 16),
            if (themes.isNotEmpty) ...[Text('Recurring themes', style: t.titleLarge), const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: [for (final th in themes) CbChip(label: '${th['word']} ×${th['count']}')]), const SizedBox(height: 16)],
            Text('Reviews', style: t.titleLarge),
            const SizedBox(height: 8),
            if (fb.isEmpty) Text('No reviews yet. Prompts go out ~2h after the event ends.', style: t.bodyMedium),
            for (final f in fb) Padding(padding: const EdgeInsets.only(bottom: 8), child: CbCard(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [for (var i = 0; i < 5; i++) Icon(i < (f['rating'] as num) ? Icons.star : Icons.star_border, size: 14, color: CbColors.warning), const SizedBox(width: 8), Text(f['displayName'] as String? ?? 'Anonymous attendee', style: t.labelMedium)]), if (f['review'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(f['review'] as String, style: t.bodyMedium))]))),
          ]);
        },
      ),
    );
  }
}

final _eventAnalyticsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, eventId) => ref.read(functionsProvider).call('getOrganizerEventAnalytics', {'eventId': eventId}));

class ClubAnalyticsScreen extends ConsumerStatefulWidget {
  const ClubAnalyticsScreen({super.key});
  @override
  ConsumerState<ClubAnalyticsScreen> createState() => _ClubAnalyticsScreenState();
}

class _ClubAnalyticsScreenState extends ConsumerState<ClubAnalyticsScreen> {
  String? _clubId;
  @override
  Widget build(BuildContext context) {
    final clubs = ref.watch(myClubsProvider);
    _clubId ??= clubs.firstOrNull?.id;
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    final data = _clubId == null ? const AsyncValue<Map<String, dynamic>>.loading() : ref.watch(_clubAnalyticsProvider(_clubId!));
    return CbPage(
      title: 'Club analytics',
      actions: [if (clubs.length > 1) DropdownButton<String>(value: _clubId, items: [for (final c in clubs) DropdownMenuItem(value: c.id, child: Text(c.name))], onChanged: (v) => setState(() => _clubId = v))],
      child: clubs.isEmpty ? const CbEmpty(icon: Icons.groups_outlined, title: 'No club linked') : data.when(
        loading: () => const CbLoading(),
        error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(_clubAnalyticsProvider(_clubId!))),
        data: (a) {
          final trend = (a['trend'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final best = (a['bestCategories'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final byDay = Map<String, dynamic>.from(a['byDay'] as Map? ?? {});
          final slots = (a['recommendedSlots'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          final sources = a['acquisitionSources'] == null ? null : Map<String, dynamic>.from(a['acquisitionSources'] as Map);
          const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [CbStatusPill(label: a['premium'] == true ? 'Premium organizer · ${a['windowDays']}-day window' : 'Basic · ${a['windowDays']}-day window', color: a['premium'] == true ? CbColors.lime : CbColors.textTertiary, icon: a['premium'] == true ? Icons.workspace_premium : Icons.info_outline)]),
            const SizedBox(height: 12),
            CbStatGrid(children: [
              CbStat(label: 'Events', value: '${a['events']}', icon: Icons.event),
              CbStat(label: 'Total RSVPs', value: '${a['totalRsvps']}', icon: Icons.how_to_reg),
              CbStat(label: 'Verified attendance', value: '${a['totalCheckins']}', icon: Icons.verified),
              CbStat(label: 'RSVP → attendance', value: Fmt.pct(a['conversion'] as num?), icon: Icons.trending_up),
              CbStat(label: 'Unique attendees', value: '${a['uniqueAttendees']}', icon: Icons.people_outline),
              CbStat(label: 'Repeat attendee rate', value: Fmt.pct(a['repeatAttendeeRate'] as num?), icon: Icons.repeat),
            ]),
            const SizedBox(height: 16),
            CbBarChart(title: 'Attendance trend', period: 'per event, oldest → newest', values: trend.map((x) => (x['rsvps'] as num).toDouble()).toList(), secondary: trend.map((x) => (x['checkins'] as num).toDouble()).toList(), labels: trend.map((x) => Fmt.monthDay(DateTime.fromMillisecondsSinceEpoch((x['startAt'] as num).toInt(), isUtc: true), tz)).toList(), primaryLabel: 'RSVPs', secondaryLabel: 'Check-ins'),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              final charts = [
                CbBarChart(title: 'Best-performing categories', period: 'avg check-ins per event', values: best.map((x) => (x['avgCheckins'] as num).toDouble()).toList(), labels: best.map((x) => x['tag'] as String).toList(), color: CbColors.lime),
                CbBarChart(title: 'Check-ins by weekday', values: days.map((d) => ((byDay[d]?['checkins'] as num?) ?? 0).toDouble()).toList(), labels: days),
              ];
              return c.maxWidth > 900 ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final ch in charts) Expanded(child: Padding(padding: const EdgeInsets.only(right: 12), child: ch))]) : Column(children: [for (final ch in charts) Padding(padding: const EdgeInsets.only(bottom: 12), child: ch)]);
            }),
            const SizedBox(height: 16),
            if (slots.isNotEmpty) ...[Text('Recommended time slots', style: t.titleLarge), const SizedBox(height: 4), Text('Based on ≥2 past events per weekday. Small samples — treat as hints.', style: t.bodySmall), const SizedBox(height: 8), Wrap(spacing: 8, children: [for (final s in slots) CbChip(label: '${s['day']} · ${s['avgCheckins']} avg', icon: Icons.schedule)]), const SizedBox(height: 16)],
            if (sources != null) ...[Text('Acquisition sources (premium)', style: t.titleLarge), const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: [for (final e in sources.entries) CbChip(label: '${e.key}: ${e.value}')])] else Text('Premium organizer unlocks acquisition sources and a 365-day window. Ask campus operations.', style: t.bodySmall),
          ]);
        },
      ),
    );
  }
}

final _clubAnalyticsProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, clubId) => ref.read(functionsProvider).call('getClubAnalytics', {'clubId': clubId}));
