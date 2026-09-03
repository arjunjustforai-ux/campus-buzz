import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../data/event_repository.dart';

/// Feed card: poster/placeholder, title, organizer, date/time, location, Tribe chips,
/// social proof, capacity, RSVP state. Kept intentionally uncluttered.
class EventCard extends ConsumerStatefulWidget {
  const EventCard({super.key, required this.event, this.reasons = const [], this.source = 'feed', this.compact = false});
  final Event event; final List<String> reasons; final String source; final bool compact;
  @override
  ConsumerState<EventCard> createState() => _EventCardState();
}

class _EventCardState extends ConsumerState<EventCard> {
  bool _impressionSent = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final tz = ref.watch(campusTimezoneProvider);
    final tribes = ref.watch(tribeMapProvider);
    final rsvp = ref.watch(myRsvpProvider(e.id)).value;
    final socialProof = ref.watch(flagProvider(FeatureFlag.socialProofEnabled));
    final me = ref.watch(userProfileProvider).value;
    final t = Theme.of(context).textTheme;
    if (!_impressionSent) {
      _impressionSent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(analyticsProvider).track('event_impression', {'eventId': e.id, 'organizerId': e.clubId, 'source': widget.source}));
    }
    final proof = socialProof ? _socialProof(e, me, tribes) : null;
    return Semantics(
      button: true,
      label: '${e.title} by ${e.clubName}, ${Fmt.dayLabel(e.startAt, tz)} ${Fmt.time(e.startAt, tz)}',
      child: CbCard(
        padding: EdgeInsets.zero,
        onTap: () { ref.read(analyticsProvider).track('event_opened', {'eventId': e.id, 'organizerId': e.clubId, 'source': widget.source}); context.push('/events/${e.id}'); },
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!widget.compact)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              child: Stack(children: [
                e.posterUrl != null && e.posterUrl!.isNotEmpty
                    ? CachedNetworkImage(imageUrl: e.posterUrl!, height: 150, fit: BoxFit.cover, width: double.infinity, placeholder: (_, __) => const CbSkeleton(height: 150, radius: 0), errorWidget: (_, __, ___) => CbPosterPlaceholder(title: e.title, height: 150, seed: e.id.hashCode))
                    : CbPosterPlaceholder(title: e.title, height: 150, seed: e.id.hashCode),
                Positioned(left: 12, top: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: CbColors.dark.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(10)), child: Text('${Fmt.dayLabel(e.startAt, tz)} · ${Fmt.time(e.startAt, tz)}', style: t.labelMedium?.copyWith(color: Colors.white)))),
                if (e.isCancelled) Positioned(right: 12, top: 12, child: CbStatusPill(label: 'Cancelled', color: CbColors.danger, icon: Icons.cancel)),
                if (!e.isCancelled && e.isCrossCampus) const Positioned(right: 12, top: 12, child: CbStatusPill(label: 'Inter-campus', color: CbColors.info, icon: Icons.public)),
                if (widget.reasons.isNotEmpty) Positioned(left: 12, bottom: 12, child: CbStatusPill(label: reasonCopy(widget.reasons.first, tribes), color: CbColors.lime, icon: Icons.auto_awesome)),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.compact) Text('${Fmt.dayLabel(e.startAt, tz)} · ${Fmt.time(e.startAt, tz)}', style: t.labelMedium?.copyWith(color: CbColors.limeText)),
              Text(e.title, style: t.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('${e.clubName} · ${e.location.name}', style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final id in e.tribeIds.take(3)) CbChip(label: '${tribes[id]?.emoji ?? ''} ${tribes[id]?.name ?? id}'.trim(), small: true, color: me?.tribeIds.contains(id) == true ? CbColors.limeText : null),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text(proof ?? (e.stats.rsvpCount > 0 ? '${e.stats.rsvpCount} going' : 'Be the first to RSVP'), style: t.bodySmall?.copyWith(color: proof != null ? CbColors.limeText : null), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (e.capacity > 0 && !e.isCancelled) Text(e.isFull ? (e.waitlistEnabled ? 'Waitlist' : 'Full') : '${e.spotsLeft} spots left', style: t.labelSmall?.copyWith(color: e.isFull ? CbColors.warning : null)),
                const SizedBox(width: 8),
                if (rsvp != null && rsvp.isActive) CbStatusPill(label: rsvp.status == 'waitlisted' ? 'Waitlisted' : 'Going', color: CbColors.success, icon: Icons.check),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  String? _socialProof(Event e, UserProfile? me, Map<String, Tribe> tribes) {
    if (me == null) return null;
    String? best; num bestN = 0;
    for (final id in me.tribeIds) {
      final n = e.tribeRsvps[id] ?? 0;
      if (n > bestN && tribes[id] != null) { bestN = n; best = tribes[id]!.name; }
    }
    if (best == null || bestN < 2) return null;
    return '$bestN $best are going.';
  }
}
