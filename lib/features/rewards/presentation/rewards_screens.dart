import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/models/models.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../buzzcoins/data/coin_repository.dart';
import '../data/reward_repository.dart';

class RewardsScreen extends ConsumerWidget {
  const RewardsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(flagProvider(FeatureFlag.rewardsEnabled));
    final balance = ref.watch(balanceProvider).value ?? const CoinBalance();
    final rewards = ref.watch(rewardsProvider);
    final redemptions = ref.watch(myRedemptionsProvider).value ?? const <Redemption>[];
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Rewards'), actions: [TextButton.icon(onPressed: () => context.push('/wallet'), icon: const Icon(Icons.receipt_long, size: 18), label: const Text('Ledger'))], bottom: const TabBar(tabs: [Tab(text: 'Store'), Tab(text: 'My redemptions')])),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: CbCard(gradient: true, child: Row(children: [
              const Icon(Icons.hexagon_rounded, color: CbColors.lime, size: 34),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${Fmt.coins(balance.balance)} BuzzCoins', style: t.headlineSmall), Text(balance.expiringSoon > 0 && balance.expiringSoonAt != null ? '${balance.expiringSoon} expire ${Fmt.date(balance.expiringSoonAt!, tz)} — spend them first.' : 'Earned by showing up. No cash value, real campus value.', style: t.bodySmall)])),
            ])),
          ),
          Expanded(
            child: TabBarView(children: [
              !on
                  ? const CbEmpty(icon: Icons.card_giftcard, title: 'Rewards launch soon', message: 'Keep earning — the store opens once your campus has 3+ redemption options.')
                  : rewards.when(
                      loading: () => const CbSkeletonList(),
                      error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(rewardsProvider)),
                      data: (list) => list.isEmpty
                          ? const CbEmpty(icon: Icons.card_giftcard, title: 'No rewards yet', message: 'Campus operations is stocking the store.')
                          : ListView.separated(padding: const EdgeInsets.all(16), itemCount: list.length, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (_, i) => _RewardTile(reward: list[i], balance: balance.balance)),
                    ),
              redemptions.isEmpty
                  ? const CbEmpty(icon: Icons.confirmation_number_outlined, title: 'Nothing redeemed yet', message: 'Your codes will show up here after you redeem a reward.')
                  : ListView.separated(padding: const EdgeInsets.all(16), itemCount: redemptions.length, separatorBuilder: (_, __) => const SizedBox(height: 10), itemBuilder: (_, i) {
                      final r = redemptions[i];
                      final color = switch (r.status) { 'fulfilled' => CbColors.success, 'issued' => CbColors.lime, 'expired' => CbColors.textTertiary, _ => CbColors.danger };
                      return CbCard(onTap: () => context.push('/rewards/redemptions/${r.id}'), padding: const EdgeInsets.all(14), child: Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.rewardTitle, style: t.titleSmall), Text('${r.code} · ${r.issuedAt == null ? '' : Fmt.date(r.issuedAt!, tz)}', style: t.bodySmall)])),
                        CbStatusPill(label: r.status == 'issued' ? 'Ready' : r.status[0].toUpperCase() + r.status.substring(1), color: color, icon: r.status == 'fulfilled' ? Icons.check : Icons.confirmation_number_outlined),
                      ]));
                    }),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _RewardTile extends ConsumerWidget {
  const _RewardTile({required this.reward, required this.balance});
  final Reward reward; final int balance;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final affordable = balance >= reward.coinCost;
    return CbCard(
      padding: EdgeInsets.zero,
      onTap: () { ref.read(analyticsProvider).track('reward_viewed', {'rewardId': reward.id}); context.push('/rewards/${reward.id}'); },
      child: Row(children: [
        ClipRRect(borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)), child: SizedBox(width: 96, height: 96, child: reward.imageUrl != null ? CachedNetworkImage(imageUrl: reward.imageUrl!, fit: BoxFit.cover) : Container(decoration: const BoxDecoration(gradient: CbColors.gradientSoft), child: Icon(_iconFor(reward.type), color: CbColors.limeText, size: 34)))),
        Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(reward.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(reward.typeLabel + (reward.soldOut ? ' · Sold out' : reward.inventory != null && reward.inventory! <= 10 ? ' · ${reward.inventory} left' : ''), style: t.bodySmall?.copyWith(color: reward.soldOut ? CbColors.warning : null)),
          const SizedBox(height: 8),
          Row(children: [CbCoinBadge(amount: reward.coinCost, prefix: ''), const SizedBox(width: 8), if (!affordable && reward.coinCost > 0) Text('${reward.coinCost - balance} more to go', style: t.labelSmall)]),
        ]))),
        const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.chevron_right, color: CbColors.textTertiary)),
      ]),
    );
  }
}

IconData _iconFor(String type) => switch (type) { 'voucher' => Icons.restaurant, 'printing_credit' => Icons.print, 'priority_access' => Icons.bolt, 'merchandise' => Icons.checkroom, 'certificate' => Icons.workspace_premium, _ => Icons.card_giftcard };

class RewardDetailScreen extends ConsumerStatefulWidget {
  const RewardDetailScreen({super.key, required this.rewardId});
  final String rewardId;
  @override
  ConsumerState<RewardDetailScreen> createState() => _RewardDetailScreenState();
}

class _RewardDetailScreenState extends ConsumerState<RewardDetailScreen> {
  bool _busy = false;
  Future<void> _redeem(Reward r) async {
    if (!await confirm(context, title: 'Redeem ${r.title}?', message: '${r.coinCost} BuzzCoins will be deducted. Codes are valid for 30 days.', confirmLabel: 'Redeem')) return;
    setState(() => _busy = true);
    try {
      final res = await ref.read(functionsProvider).call('redeemReward', {'rewardId': r.id});
      if (mounted) context.pushReplacement('/rewards/redemptions/${res['redemptionId']}');
    } catch (e) {
      if (mounted) showCbError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reward = ref.watch(rewardProvider(widget.rewardId));
    final balance = ref.watch(balanceProvider).value?.balance ?? 0;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Reward')),
      body: reward.when(
        loading: () => const CbLoading(),
        error: (e, _) => CbErrorView(error: e),
        data: (r) {
          if (r == null) return const CbEmpty(title: 'Reward not found');
          final short = r.coinCost - balance;
          return ListView(padding: const EdgeInsets.all(16), children: [
            ClipRRect(borderRadius: BorderRadius.circular(18), child: SizedBox(height: 180, child: r.imageUrl != null ? CachedNetworkImage(imageUrl: r.imageUrl!, fit: BoxFit.cover) : Container(decoration: const BoxDecoration(gradient: CbColors.gradientSoft), child: Icon(_iconFor(r.type), color: CbColors.limeText, size: 64)))),
            const SizedBox(height: 16),
            Row(children: [Expanded(child: Text(r.title, style: t.headlineSmall)), CbCoinBadge(amount: r.coinCost, prefix: '', large: true)]),
            const SizedBox(height: 6),
            Text(r.typeLabel + (r.faceValue != null && r.faceValue! > 0 ? ' · worth ${Fmt.rupees(r.faceValue!)}' : ''), style: t.bodyMedium),
            const SizedBox(height: 16),
            Text(r.description, style: t.bodyLarge?.copyWith(color: CbColors.textSecondary)),
            if (r.redemptionInstructions.isNotEmpty) ...[const SizedBox(height: 16), Text('How to redeem', style: t.titleMedium), const SizedBox(height: 4), Text(r.redemptionInstructions, style: t.bodyMedium)],
            if (r.terms.isNotEmpty) ...[const SizedBox(height: 16), Text('Terms', style: t.titleMedium), const SizedBox(height: 4), Text(r.terms, style: t.bodySmall)],
            const SizedBox(height: 24),
            if (r.type == 'certificate') FilledButton(onPressed: () => context.push('/history'), child: const Text('Pick an event from your history'))
            else FilledButton(onPressed: _busy || r.soldOut || short > 0 ? null : () => _redeem(r), child: Text(r.soldOut ? 'Sold out' : short > 0 ? 'You need $short more BuzzCoins' : 'Redeem for ${r.coinCost} BuzzCoins')),
            if (r.perUserLimit > 0) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Limit ${r.perUserLimit} per student.', style: t.bodySmall, textAlign: TextAlign.center)),
          ]);
        },
      ),
    );
  }
}

class RedemptionDetailScreen extends ConsumerWidget {
  const RedemptionDetailScreen({super.key, required this.redemptionId});
  final String redemptionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final red = ref.watch(redemptionProvider(redemptionId));
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Your code')),
      body: red.when(
        loading: () => const CbLoading(),
        error: (e, _) => CbErrorView(error: e),
        data: (r) {
          if (r == null) return const CbEmpty(title: 'Redemption not found');
          final live = r.status == 'issued' && (r.expiresAt == null || r.expiresAt!.isAfter(DateTime.now().toUtc()));
          return ListView(padding: const EdgeInsets.all(20), children: [
            Text(r.rewardTitle, style: t.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Center(child: CbStatusPill(label: r.status == 'fulfilled' ? 'Used ${r.fulfilledAt == null ? '' : Fmt.date(r.fulfilledAt!, tz)}' : live ? 'Ready to use' : r.status == 'cancelled' ? 'Refunded' : 'Expired', color: r.status == 'fulfilled' ? CbColors.success : live ? CbColors.lime : CbColors.textTertiary, icon: r.status == 'fulfilled' ? Icons.check : Icons.confirmation_number_outlined)),
            const SizedBox(height: 24),
            Center(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: QrImageView(data: r.code, size: 200, backgroundColor: Colors.white))),
            const SizedBox(height: 20),
            Center(child: InkWell(onTap: () { Clipboard.setData(ClipboardData(text: r.code)); showCbSnack(context, 'Code copied'); }, child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(color: CbColors.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: CbColors.border)), child: Text(r.code, style: t.displaySmall?.copyWith(letterSpacing: 4))))),
            const SizedBox(height: 20),
            if (r.redemptionInstructions != null) Text(r.redemptionInstructions!, style: t.bodyLarge, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text('Issued ${r.issuedAt == null ? '' : Fmt.dateTime(r.issuedAt!, tz)}${r.expiresAt != null ? ' · valid until ${Fmt.date(r.expiresAt!, tz)}' : ''} · ${r.coinCost} BuzzCoins', style: t.bodySmall, textAlign: TextAlign.center),
          ]);
        },
      ),
    );
  }
}

class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);
    final balance = ref.watch(balanceProvider).value ?? const CoinBalance();
    final economy = ref.watch(economyProvider);
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('BuzzCoin ledger')),
      body: ledger.when(
        loading: () => const CbSkeletonList(height: 64),
        error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(ledgerProvider)),
        data: (entries) => ListView(padding: const EdgeInsets.all(16), children: [
          CbStatGrid(minTileWidth: 150, children: [
            CbStat(label: 'Balance', value: Fmt.coins(balance.balance), icon: Icons.hexagon_rounded, color: CbColors.limeText),
            CbStat(label: 'Earned all-time', value: Fmt.coins(balance.lifetimeEarned), icon: Icons.trending_up),
            CbStat(label: 'Redeemed', value: Fmt.coins(balance.lifetimeRedeemed), icon: Icons.card_giftcard),
            CbStat(label: 'Expired', value: Fmt.coins(balance.lifetimeExpired), icon: Icons.hourglass_bottom, hint: 'Coins expire ${economy.coinExpiryDays} days after you earn them'),
          ]),
          const SizedBox(height: 16),
          CbCard(padding: const EdgeInsets.all(12), child: Text('How to earn: RSVP +${economy.rsvpReward} · verified check-in +${economy.checkinReward} (${economy.streakMultiplier}x after ${economy.streakThresholdWeeks} weeks in a row) · feedback +${economy.feedbackReward} · friend\'s first event +${economy.referralReward}', style: t.bodySmall)),
          const SizedBox(height: 16),
          if (entries.isEmpty) const CbEmpty(icon: Icons.receipt_long, title: 'No activity yet', message: 'RSVP to an event to earn your first BuzzCoins.'),
          for (final e in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(backgroundColor: e.amount >= 0 ? CbColors.lime.withValues(alpha: 0.15) : CbColors.danger.withValues(alpha: 0.15), child: Icon(e.amount >= 0 ? Icons.add : Icons.remove, color: e.amount >= 0 ? CbColors.lime : CbColors.danger, size: 18)),
              title: Text(e.label),
              subtitle: Text('${Fmt.dateTime(e.createdAt, tz)}${e.expiresAt != null && e.type == 'credit' ? ' · expires ${Fmt.date(e.expiresAt!, tz)}' : ''}'),
              trailing: Text('${e.amount >= 0 ? '+' : ''}${e.amount}', style: t.titleMedium?.copyWith(color: e.amount >= 0 ? CbColors.limeText : CbColors.danger)),
            ),
        ]),
      ),
    );
  }
}
