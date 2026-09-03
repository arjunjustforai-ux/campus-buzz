import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart' hide Feedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/models/models.dart';
import '../../../core/navigation/deep_links.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../data/event_repository.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;
  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  bool _busy = false;

  Future<void> _rsvp(Event e, Rsvp? current) async {
    setState(() => _busy = true);
    try {
      final actions = ref.read(eventActionsProvider);
      if (current != null && current.isActive) {
        if (!await confirm(context, title: 'Cancel your RSVP?', message: "You keep any BuzzCoins you've earned. Re-RSVPing later won't earn them again.", confirmLabel: 'Cancel RSVP', destructive: true)) return;
        await actions.cancelRsvp(e.id);
        if (mounted) showCbSnack(context, 'RSVP cancelled.');
      } else {
        final r = await actions.rsvp(e.id, source: 'detail');
        final coins = (r['coinsAwarded'] as num?)?.toInt() ?? 0;
        if (mounted) showCbSnack(context, r['status'] == 'waitlisted' ? "You're on the waitlist. We'll tell you if a spot opens." : coins > 0 ? "You're in. +$coins BuzzCoins." : "You're in.", icon: Icons.celebration_outlined);
      }
    } catch (e) {
      if (mounted) showCbError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(Event e) async {
    ref.read(analyticsProvider).track('referral_shared', {'eventId': e.id, 'source': 'event_share'});
    final tz = ref.read(campusTimezoneProvider);
    await SharePlus.instance.share(ShareParams(text: '${e.title} — ${Fmt.dateTime(e.startAt, tz)} at ${e.location.name}. RSVP on CampusBuzz: ${DeepLinkService.eventShareUrl(e.id)}', subject: e.title));
  }

  Future<void> _openMaps(Event e) async {
    final q = e.location.lat != null && e.location.lng != null ? '${e.location.lat},${e.location.lng}' : Uri.encodeComponent('${e.location.name} ${e.location.address}');
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) showCbSnack(context, "Couldn't open maps on this device.", error: true);
  }

  Future<void> _report(Event e) async {
    final reason = await askReason(context, title: 'Report this event', hint: "What's wrong? (inaccurate, inappropriate, suspicious…)");
    if (reason == null) return;
    try {
      await ref.read(eventActionsProvider).report(e.campusId, 'event', e.id, reason);
      if (mounted) showCbSnack(context, 'Thanks — campus operations will review it.');
    } catch (err) {
      if (mounted) showCbError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = ref.watch(eventProvider(widget.eventId));
    final tz = ref.watch(campusTimezoneProvider);
    final tribes = ref.watch(tribeMapProvider);
    final rsvp = ref.watch(myRsvpProvider(widget.eventId)).value;
    final checkin = ref.watch(myCheckinProvider(widget.eventId)).value;
    final feedback = ref.watch(myFeedbackProvider(widget.eventId)).value;
    final reviewsOn = ref.watch(flagProvider(FeatureFlag.reviewsEnabled));
    final socialProof = ref.watch(flagProvider(FeatureFlag.socialProofEnabled));
    final me = ref.watch(userProfileProvider).value;
    final roles = ref.watch(rolesProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: event.when(
        loading: () => const CbLoading(),
        error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(eventProvider(widget.eventId))),
        data: (e) {
          if (e == null) return const CbEmpty(title: 'Event not found', message: 'It may have been removed by the organizer.');
          final canManage = roles.contains(Role.campusAdmin) || (roles.contains(Role.organizer) && (e.organizerUid == me?.uid || (ref.watch(membershipProvider).value?.clubIds.contains(e.clubId) ?? false)));
          final reviews = reviewsOn ? ref.watch(eventReviewsProvider(e.id)).value ?? const <Feedback>[] : const <Feedback>[];
          final proof = socialProof ? _proof(e, me, tribes) : null;
          return CustomScrollView(slivers: [
            SliverAppBar(
              expandedHeight: 240, pinned: true,
              actions: [
                IconButton(tooltip: 'Share', onPressed: () => _share(e), icon: const Icon(Icons.ios_share)),
                PopupMenuButton<String>(onSelected: (v) { if (v == 'report') _report(e); if (v == 'manage') context.push('/organizer/events/${e.id}'); }, itemBuilder: (_) => [if (canManage) const PopupMenuItem(value: 'manage', child: Text('Manage event')), const PopupMenuItem(value: 'report', child: Text('Report event'))]),
              ],
              flexibleSpace: FlexibleSpaceBar(background: e.posterUrl != null && e.posterUrl!.isNotEmpty ? CachedNetworkImage(imageUrl: e.posterUrl!, fit: BoxFit.cover, errorWidget: (_, __, ___) => CbPosterPlaceholder(title: e.title, height: 240, seed: e.id.hashCode)) : CbPosterPlaceholder(title: e.title, height: 240, seed: e.id.hashCode)),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (e.isCancelled) const CbStatusPill(label: 'Cancelled', color: CbColors.danger, icon: Icons.cancel),
                    if (e.isCompleted) const CbStatusPill(label: 'Completed', color: CbColors.textTertiary, icon: Icons.check),
                    if (e.isCrossCampus) CbStatusPill(label: 'Hosted by ${e.campusId}', color: CbColors.info, icon: Icons.public),
                    if (checkin != null) const CbStatusPill(label: 'Checked in', color: CbColors.success, icon: Icons.verified),
                    if (e.checkinActive && !e.isCancelled) const CbStatusPill(label: 'Check-in open', color: CbColors.lime, icon: Icons.qr_code),
                  ]),
                  const SizedBox(height: 10),
                  Text(e.title, style: t.headlineMedium),
                  const SizedBox(height: 6),
                  InkWell(onTap: () => context.push('/explore?q=${Uri.encodeComponent(e.clubName)}'), child: Text(e.clubName, style: t.titleMedium?.copyWith(color: CbColors.limeText))),
                  if (e.isCancelled && e.cancellationReason != null) Padding(padding: const EdgeInsets.only(top: 10), child: CbCard(color: CbColors.danger.withValues(alpha: 0.1), borderColor: CbColors.danger, padding: const EdgeInsets.all(12), child: Text('Cancelled: ${e.cancellationReason}', style: t.bodyMedium))),
                  const SizedBox(height: 16),
                  _InfoRow(icon: Icons.calendar_today, title: Fmt.longDate(e.startAt, tz), subtitle: '${Fmt.time(e.startAt, tz)} – ${Fmt.time(e.endAt, tz)}'),
                  _InfoRow(icon: Icons.place_outlined, title: e.location.name, subtitle: e.location.address.isEmpty ? 'Open in Maps' : e.location.address, onTap: () => _openMaps(e)),
                  if (e.capacity > 0) _InfoRow(icon: Icons.people_outline, title: e.isFull ? (e.waitlistEnabled ? 'Full · waitlist open' : 'Full') : '${e.spotsLeft} of ${e.capacity} spots left', subtitle: '${e.stats.rsvpCount} going${e.stats.waitlistCount > 0 ? ' · ${e.stats.waitlistCount} waitlisted' : ''}'),
                  if (e.capacity == 0) _InfoRow(icon: Icons.people_outline, title: '${e.stats.rsvpCount} going', subtitle: 'Open capacity'),
                  if (e.contact.isNotEmpty) _InfoRow(icon: Icons.contact_support_outlined, title: e.contact, subtitle: 'Organizer contact'),
                  if (proof != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(proof, style: t.titleSmall?.copyWith(color: CbColors.limeText))),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [for (final id in e.tribeIds) CbChip(label: '${tribes[id]?.emoji ?? ''} ${tribes[id]?.name ?? id}'.trim(), onTap: () => context.push('/tribes/$id')), for (final tag in e.tags) CbChip(label: '#$tag', small: true, onTap: () => context.push('/explore?q=${Uri.encodeComponent(tag)}'))]),
                  const SizedBox(height: 20),
                  Text('About', style: t.titleLarge),
                  const SizedBox(height: 8),
                  Text(e.description, style: t.bodyLarge?.copyWith(color: CbColors.textSecondary, height: 1.5)),
                  const SizedBox(height: 24),
                  if (checkin != null) ...[
                    CbCard(gradient: true, child: Row(children: [
                      const Icon(Icons.verified, color: CbColors.limeText, size: 28),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("You're checked in.", style: t.titleMedium), Text(checkin.coinsAwarded > 0 ? '+${checkin.coinsAwarded} BuzzCoins${checkin.multiplierApplied ? ' (streak 2x)' : ''} · ${checkin.method == 'manual' ? 'manual check-in' : 'QR verified'}' : 'QR verified', style: t.bodySmall)])),
                      if (e.certificateEnabled) TextButton(onPressed: () => context.push('/events/${e.id}/certificate'), child: const Text('Certificate')),
                    ])),
                    const SizedBox(height: 12),
                    if (reviewsOn && feedback == null) FilledButton.tonalIcon(onPressed: () => context.push('/events/${e.id}/feedback'), icon: const Icon(Icons.star_outline), label: const Text('Rate this event · +10 BuzzCoins')),
                    const SizedBox(height: 20),
                  ],
                  if (reviewsOn && (e.stats.feedbackCount > 0 || reviews.isNotEmpty)) ...[
                    Row(children: [Text('Reviews', style: t.titleLarge), const SizedBox(width: 10), const Icon(Icons.star, color: CbColors.warning, size: 18), Text(' ${e.stats.ratingAvg.toStringAsFixed(1)} · ${e.stats.feedbackCount}', style: t.titleMedium)]),
                    const SizedBox(height: 8),
                    for (final r in reviews.take(10)) if (r.review != null && r.review!.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: CbCard(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [for (var i = 0; i < 5; i++) Icon(i < r.rating ? Icons.star : Icons.star_border, size: 14, color: CbColors.warning), const SizedBox(width: 8), Text(r.displayName ?? 'Verified attendee', style: t.labelMedium)]), const SizedBox(height: 6), Text(r.review!, style: t.bodyMedium)]))),
                    const SizedBox(height: 20),
                  ],
                  const SizedBox(height: 80),
                ]),
              ),
            ),
          ]);
        },
      ),
      bottomNavigationBar: event.value == null ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Builder(builder: (context) {
            final e = event.value!;
            final going = rsvp != null && rsvp.isActive;
            if (e.isCancelled) return const OutlinedButton(onPressed: null, child: Text('Event cancelled'));
            if (checkin != null) return FilledButton.icon(onPressed: () => context.push('/events/${e.id}/feedback'), icon: const Icon(Icons.verified), label: const Text('Checked in · rate it'));
            if (e.isCompleted || e.isPast) return const OutlinedButton(onPressed: null, child: Text('This event has ended'));
            if (e.checkinActive && going) return Row(children: [Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _rsvp(e, rsvp), child: const Text('Cancel RSVP'))), const SizedBox(width: 10), Expanded(child: FilledButton.icon(onPressed: () => context.go('/scan'), icon: const Icon(Icons.qr_code_scanner), label: const Text('Scan to check in')))]);
            return FilledButton(
              style: going ? FilledButton.styleFrom(backgroundColor: CbColors.surface3) : null,
              onPressed: _busy ? null : () => _rsvp(e, rsvp),
              child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(going ? (rsvp.status == 'waitlisted' ? "Waitlisted · tap to leave" : "You're going · tap to cancel") : e.isFull ? (e.waitlistEnabled ? 'Join waitlist' : 'Event full') : 'RSVP · +${ref.watch(economyProvider).rsvpReward} BuzzCoins'),
            );
          }),
        ),
      ),
    );
  }

  String? _proof(Event e, UserProfile? me, Map<String, Tribe> tribes) {
    if (me == null) return null;
    final parts = <String>[];
    for (final id in me.tribeIds) { final n = e.tribeRsvps[id] ?? 0; if (n >= 2 && tribes[id] != null) parts.add('$n ${tribes[id]!.name}'); }
    if (parts.isEmpty) return null;
    return '${parts.take(2).join(' and ')} are going.';
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.title, required this.subtitle, this.onTap});
  final IconData icon; final String title, subtitle; final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      Container(width: 40, height: 40, decoration: BoxDecoration(color: CbColors.surface2, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 20, color: CbColors.limeText)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: t.titleSmall), Text(subtitle, style: t.bodySmall)])),
      if (onTap != null) const Icon(Icons.open_in_new, size: 16, color: CbColors.textTertiary),
    ])));
  }
}
