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
import '../../buzzcoins/data/coin_repository.dart';
import '../../events/data/event_repository.dart';
import '../../events/presentation/event_card.dart';
import '../../notifications/application/push_service.dart';
import '../../quests/data/quest_repository.dart';

/// Student home: greeting, BuzzCoin/streak strip, quick Tribe filter, feed.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _tribeFilter;
  bool _tracked = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final campus = ref.watch(campusProvider).value;
    final tz = ref.watch(campusTimezoneProvider);
    final tribes = ref.watch(tribesProvider).value ?? const <Tribe>[];
    final events = ref.watch(upcomingEventsProvider);
    final ranked = ref.watch(recommendedFeedProvider);
    final personalized = ref.watch(flagProvider(FeatureFlag.personalizedFeedEnabled));
    final coinsOn = ref.watch(flagProvider(FeatureFlag.buzzcoinsEnabled));
    final balance = ref.watch(balanceProvider).value ?? const CoinBalance();
    final stats = ref.watch(participationStatsProvider).value ?? const ParticipationStats();
    final economy = ref.watch(economyProvider);
    final rsvps = ref.watch(myUpcomingRsvpsProvider).value ?? const <Rsvp>[];
    final banner = ref.watch(foregroundNotificationProvider);
    final quests = ref.watch(liveQuestsProvider).value ?? const <Quest>[];
    final t = Theme.of(context).textTheme;
    if (!_tracked) { _tracked = true; WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(analyticsProvider).track('feed_viewed', {'screen': 'home'})); }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async { ref.invalidate(recommendedFeedProvider); ref.invalidate(upcomingEventsProvider); },
        child: CustomScrollView(slivers: [
          SliverAppBar(
            pinned: false, floating: true,
            title: Row(children: [Container(width: 28, height: 28, decoration: BoxDecoration(gradient: CbColors.gradient, borderRadius: BorderRadius.circular(9)), child: const Icon(Icons.bolt, color: CbColors.dark, size: 18)), const SizedBox(width: 8), Text('CampusBuzz', style: t.titleLarge)]),
            actions: [
              IconButton(tooltip: 'Notifications', onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_outlined)),
              IconButton(tooltip: 'Tribe leaderboard', onPressed: () => context.push('/tribes/leaderboard'), icon: const Icon(Icons.emoji_events_outlined)),
            ],
          ),
          if (banner != null)
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: CbCard(color: CbColors.surface2, onTap: () { ref.read(foregroundNotificationProvider.notifier).clear(); if (banner.route != null) context.push(banner.route!); }, padding: const EdgeInsets.all(12), child: Row(children: [const Icon(Icons.notifications_active, color: CbColors.limeText), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(banner.title, style: t.titleSmall), Text(banner.body, style: t.bodySmall)])), IconButton(onPressed: () => ref.read(foregroundNotificationProvider.notifier).clear(), icon: const Icon(Icons.close, size: 18))])))),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_greeting(profile?.displayName), style: t.headlineMedium),
                Text(campus?.name ?? '', style: t.bodyMedium),
                const SizedBox(height: 14),
                if (coinsOn)
                  Row(children: [
                    Expanded(child: _StatusTile(icon: Icons.hexagon_rounded, label: 'BuzzCoins', value: Fmt.coins(balance.balance), hint: balance.expiringSoon > 0 ? '${balance.expiringSoon} expiring soon' : 'Tap to see your ledger', onTap: () => context.push('/wallet'))),
                    const SizedBox(width: 10),
                    Expanded(child: _StatusTile(icon: Icons.local_fire_department, label: 'Streak', value: '${stats.streak} wk', hint: stats.multiplierActive ? '${economy.streakMultiplier}x check-in rewards on' : '${(economy.streakThresholdWeeks - stats.streak).clamp(0, 99)} more for ${economy.streakMultiplier}x', onTap: () => context.push('/history'))),
                  ]),
              ]),
            ),
          ),
          if (rsvps.isNotEmpty)
            SliverToBoxAdapter(child: CbSection(title: "You're going", action: () => context.push('/history'), actionLabel: 'History', child: SizedBox(height: 92, child: ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: rsvps.length, separatorBuilder: (_, __) => const SizedBox(width: 10), itemBuilder: (_, i) => SizedBox(width: 240, child: CbCard(padding: const EdgeInsets.all(12), onTap: () => context.push('/events/${rsvps[i].eventId}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Text(rsvps[i].startAt == null ? '' : '${Fmt.dayLabel(rsvps[i].startAt!, tz)} · ${Fmt.time(rsvps[i].startAt!, tz)}', style: t.labelMedium?.copyWith(color: CbColors.limeText)), const SizedBox(height: 4), Text(rsvps[i].eventTitle, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)]))))))),
          if (quests.isNotEmpty)
            SliverToBoxAdapter(child: CbSection(title: 'Sponsored quests', action: () => context.push('/quests'), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: CbCard(gradient: true, onTap: () => context.push('/quests/${quests.first.id}'), child: Row(children: [const Icon(Icons.workspace_premium, color: CbColors.limeText), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(quests.first.title, style: t.titleMedium), Text('${quests.first.sponsorDisclosure} · +${quests.first.rewardCoins} BuzzCoins', style: t.bodySmall)])), const Icon(Icons.chevron_right)]))))),
          SliverToBoxAdapter(
            child: CbSection(
              title: "What's happening",
              subtitle: personalized && ranked.value?.variant == 'personalized' ? 'Ranked for your Tribes' : 'Soonest first',
              action: () => context.go('/explore'),
              actionLabel: 'Search',
              child: SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
                CbChip(label: 'All', selected: _tribeFilter == null, onTap: () => setState(() => _tribeFilter = null)),
                const SizedBox(width: 8),
                for (final tr in [...tribes]..sort((a, b) => (profile?.tribeIds.contains(b.id) == true ? 1 : 0) - (profile?.tribeIds.contains(a.id) == true ? 1 : 0)))
                  Padding(padding: const EdgeInsets.only(right: 8), child: CbChip(label: '${tr.emoji} ${tr.name}'.trim(), selected: _tribeFilter == tr.id, onTap: () => setState(() => _tribeFilter = _tribeFilter == tr.id ? null : tr.id))),
              ])),
            ),
          ),
          events.when(
            loading: () => const SliverToBoxAdapter(child: CbSkeletonList(count: 3)),
            error: (e, _) => SliverToBoxAdapter(child: CbErrorView(error: e, onRetry: () => ref.invalidate(upcomingEventsProvider))),
            data: (list) {
              var items = list.where((e) => _tribeFilter == null || e.tribeIds.contains(_tribeFilter)).toList();
              final reasons = <String, List<String>>{};
              if (personalized && ranked.value != null && ranked.value!.items.isNotEmpty && _tribeFilter == null) {
                final order = {for (var i = 0; i < ranked.value!.items.length; i++) ranked.value!.items[i].eventId: i};
                for (final r in ranked.value!.items) reasons[r.eventId] = r.reasons;
                items.sort((a, b) => (order[a.id] ?? 1 << 20).compareTo(order[b.id] ?? 1 << 20));
              }
              if (items.isEmpty) {
                return SliverFillRemaining(hasScrollBody: false, child: CbEmpty(icon: Icons.event_busy, title: _tribeFilter == null ? "Nothing's posted yet" : 'Nothing for this Tribe yet', message: _tribeFilter == null ? 'Organizers post here first. Check back soon, or search past favourites.' : 'Try another Tribe or clear the filter.', actionLabel: _tribeFilter == null ? 'Explore' : 'Clear filter', action: () => _tribeFilter == null ? context.go('/explore') : setState(() => _tribeFilter = null)));
              }
              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                sliver: SliverList.separated(itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (_, i) => EventCard(event: items[i], reasons: reasons[items[i].id] ?? const [], source: 'feed')),
              );
            },
          ),
        ]),
      ),
    );
  }

  String _greeting(String? name) {
    final h = DateTime.now().hour;
    final first = (name ?? '').split(' ').first;
    final g = h < 12 ? 'Morning' : h < 17 ? 'Afternoon' : 'Evening';
    return first.isEmpty ? '$g.' : '$g, $first.';
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.icon, required this.label, required this.value, required this.hint, required this.onTap});
  final IconData icon; final String label, value, hint; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return CbCard(onTap: onTap, padding: const EdgeInsets.all(12), child: Row(children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: CbColors.lime.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: CbColors.lime, size: 20)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: t.labelSmall), Text(value, style: t.titleLarge), Text(hint, style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis)])),
    ]));
  }
}
