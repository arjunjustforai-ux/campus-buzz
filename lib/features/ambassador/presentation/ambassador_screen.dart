import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/models/models.dart';
import '../../../core/navigation/deep_links.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../buzzcoins/data/coin_repository.dart';
import '../../events/data/event_repository.dart';

final myReferralsProvider = StreamProvider<List<Referral>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.referrals).where('referrerUid', isEqualTo: uid).orderBy('signupAt', descending: true).limit(200).snapshots().map((s) => s.docs.map(Referral.fromDoc).toList());
});

/// Ambassador performance: referral link, weekly onboarding target, verified referrals, events attended, incentives, badges, toolkit.
class AmbassadorScreen extends ConsumerWidget {
  const AmbassadorScreen({super.key});
  static const weeklyTarget = 10;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(userProfileProvider).value;
    final refs = ref.watch(myReferralsProvider);
    final checkins = ref.watch(myCheckinsProvider).value ?? const <Checkin>[];
    final ledger = ref.watch(ledgerProvider).value ?? const <LedgerEntry>[];
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    final code = me?.referralCode ?? '';
    final link = DeepLinkService.referralUrl(code);
    return Scaffold(
      appBar: AppBar(title: const Text('Ambassador')),
      body: refs.when(
        loading: () => const CbLoading(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) {
          final weekAgo = DateTime.now().toUtc().subtract(const Duration(days: 7));
          final thisWeek = list.where((r) => r.signupAt != null && r.signupAt!.isAfter(weekAgo)).length;
          final verified = list.where((r) => r.rewardAwarded).length;
          final incentives = ledger.where((e) => e.reason == 'referral').fold<int>(0, (s, e) => s + e.amount);
          final badges = [if (list.isNotEmpty) ('First referral', Icons.rocket_launch), if (verified >= 5) ('5 verified', Icons.verified), if (verified >= 25) ('25 verified', Icons.military_tech), if (thisWeek >= weeklyTarget) ('Weekly target hit', Icons.emoji_events)];
          return ListView(padding: const EdgeInsets.all(16), children: [
            CbCard(gradient: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your referral link', style: t.labelMedium),
              const SizedBox(height: 4),
              SelectableText(link, style: t.titleMedium),
              const SizedBox(height: 10),
              Row(children: [
                FilledButton.icon(onPressed: () => SharePlus.instance.share(ShareParams(text: 'Join me on CampusBuzz — every event on campus, verified check-ins, real rewards. $link', subject: 'CampusBuzz')), icon: const Icon(Icons.ios_share, size: 18), label: const Text('Share')),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: code)); showCbSnack(context, 'Code $code copied'); }, icon: const Icon(Icons.copy, size: 18), label: Text(code)),
              ]),
            ])),
            const SizedBox(height: 16),
            CbStatGrid(minTileWidth: 150, children: [
              CbStat(label: 'Onboarded this week', value: '$thisWeek / $weeklyTarget', band: thisWeek >= weeklyTarget ? 'green' : thisWeek >= weeklyTarget / 2 ? 'yellow' : 'red', icon: Icons.person_add_alt),
              CbStat(label: 'Total referred', value: '${list.length}', icon: Icons.group_outlined),
              CbStat(label: 'Verified attendance', value: '$verified', hint: 'Referred students who showed up', icon: Icons.verified_outlined),
              CbStat(label: 'Events you attended', value: '${checkins.length}', icon: Icons.event_available),
              CbStat(label: 'Incentives earned', value: '+$incentives', hint: 'BuzzCoins from referrals', icon: Icons.hexagon_rounded, color: CbColors.limeText),
            ]),
            const SizedBox(height: 16),
            if (badges.isNotEmpty) ...[Text('Badges', style: t.titleLarge), const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: [for (final b in badges) CbChip(label: b.$1, icon: b.$2, selected: true)]), const SizedBox(height: 16)],
            Text('Referrals', style: t.titleLarge),
            if (list.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: CbEmpty(icon: Icons.person_add_alt, title: 'No referrals yet', message: 'Share your link in class groups. You earn when they attend their first event.')),
            for (final r in list.take(50)) ListTile(contentPadding: EdgeInsets.zero, leading: Icon(r.rewardAwarded ? Icons.verified : Icons.hourglass_empty, color: r.rewardAwarded ? CbColors.success : CbColors.textTertiary), title: Text('Student ${r.referredUid.substring(0, 6)}…'), subtitle: Text('Joined ${r.signupAt == null ? '' : Fmt.date(r.signupAt!, tz)}${r.rewardAwarded && r.firstAttendanceAt != null ? ' · first event ${Fmt.date(r.firstAttendanceAt!, tz)}' : ' · not attended yet'}')),
            const SizedBox(height: 16),
            Text('Toolkit', style: t.titleLarge),
            const SizedBox(height: 8),
            for (final m in const ['"Every event on campus, in one feed. RSVP in one tap."', '"Scan the QR at the door — you earn BuzzCoins for showing up."', '"100 BuzzCoins = ₹50 at the canteen. Six events and you\'re there."', 'Ask organizers to post at least a week early — reminders go out 24h and 1h before.'])
              Padding(padding: const EdgeInsets.only(bottom: 8), child: CbCard(padding: const EdgeInsets.all(12), onTap: () { Clipboard.setData(ClipboardData(text: m)); showCbSnack(context, 'Copied'); }, child: Row(children: [Expanded(child: Text(m, style: t.bodyMedium)), const Icon(Icons.copy, size: 16, color: CbColors.textTertiary)]))),
            const SizedBox(height: 8),
            Text('Only aggregate referral outcomes are shown — no student PII.', style: t.bodySmall),
          ]);
        },
      ),
    );
  }
}
