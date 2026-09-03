import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/models/models.dart';
import '../../../core/navigation/deep_links.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';
import '../../buzzcoins/data/coin_repository.dart';
import '../../events/data/event_repository.dart';
import '../../workspace/presentation/workspace_switcher.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(userProfileProvider).value;
    final campus = ref.watch(campusProvider).value;
    final tribes = ref.watch(tribeMapProvider);
    final balance = ref.watch(balanceProvider).value ?? const CoinBalance();
    final stats = ref.watch(participationStatsProvider).value ?? const ParticipationStats();
    final checkins = ref.watch(myCheckinsProvider).value ?? const <Checkin>[];
    final ws = ref.watch(workspacesProvider);
    final roles = ref.watch(rolesProvider);
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    if (me == null) return const Scaffold(body: CbLoading());
    final badges = [if (checkins.isNotEmpty) ('First check-in', Icons.verified), if (checkins.length >= 5) ('5 events', Icons.local_activity), if (checkins.length >= 15) ('Regular', Icons.military_tech), if (stats.streak >= 3) ('On a streak', Icons.local_fire_department), if (roles.contains(Role.organizer)) ('Organizer', Icons.event_available), if (roles.contains(Role.ambassador)) ('Ambassador', Icons.campaign)];
    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), actions: [IconButton(tooltip: 'Settings', onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Stack(children: [CbAvatar(name: me.displayName, url: me.avatarUrl, size: 72), Positioned(right: -4, bottom: -4, child: IconButton.filled(iconSize: 16, style: IconButton.styleFrom(backgroundColor: CbColors.surface3), onPressed: () => _pickAvatar(context, ref, me.uid), icon: const Icon(Icons.edit)))]),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(me.displayName, style: t.headlineSmall), Text(campus?.name ?? '', style: t.bodyMedium), if (me.primaryTribeId != null && tribes[me.primaryTribeId] != null) Padding(padding: const EdgeInsets.only(top: 6), child: CbChip(label: '${tribes[me.primaryTribeId]!.emoji} ${tribes[me.primaryTribeId]!.name}', selected: true, small: true))])),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final id in me.tribeIds) if (tribes[id] != null) CbChip(label: '${tribes[id]!.emoji} ${tribes[id]!.name}'.trim(), onTap: () => context.push('/tribes/$id')), ActionChip(avatar: const Icon(Icons.edit, size: 14), label: const Text('Edit Tribes'), onPressed: () => _editTribes(context, ref, me))]),
        const SizedBox(height: 16),
        CbStatGrid(minTileWidth: 110, children: [
          CbStat(label: 'BuzzCoins', value: Fmt.coins(balance.balance), icon: Icons.hexagon_rounded, color: CbColors.limeText, onTap: () => context.push('/wallet')),
          CbStat(label: 'Streak', value: '${stats.streak} wk', icon: Icons.local_fire_department, color: stats.multiplierActive ? CbColors.orangeText : null),
          CbStat(label: 'Verified events', value: '${checkins.length}', icon: Icons.verified, onTap: () => context.push('/history')),
        ]),
        const SizedBox(height: 16),
        if (badges.isNotEmpty) ...[Text('Badges', style: t.titleLarge), const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: [for (final b in badges) CbChip(label: b.$1, icon: b.$2)]), const SizedBox(height: 16)],
        if (ws.length > 1) ...[Text('Workspaces', style: t.titleLarge), const SizedBox(height: 8), for (final w in ws.skip(1)) ListTile(contentPadding: EdgeInsets.zero, leading: Icon(w.icon), title: Text(w.label), trailing: const Icon(Icons.chevron_right), onTap: () => context.go(w.path)), const SizedBox(height: 8)],
        Text('Recent participation', style: t.titleLarge),
        if (checkins.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text("No verified events yet. Your Tribe's waiting.")),
        for (final c in checkins.take(5)) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.verified, color: CbColors.success), title: Text(c.eventTitle), subtitle: Text(Fmt.date(c.at, tz)), trailing: CbCoinBadge(amount: c.coinsAwarded), onTap: () => context.push('/events/${c.eventId}')),
        TextButton(onPressed: () => context.push('/history'), child: const Text('Full history & certificates')),
        const Divider(height: 32),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.people_outline), title: const Text('Friends'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/friends')),
        if (ref.watch(flagProvider(FeatureFlag.referralsEnabled))) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.card_giftcard_outlined), title: const Text('Invite friends'), subtitle: Text('+${ref.watch(economyProvider).referralReward} BuzzCoins when they attend their first event'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/referrals')),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.workspace_premium_outlined), title: const Text('Sponsored quests'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/quests')),
        if (!roles.contains(Role.organizer)) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event_available_outlined), title: const Text('Become an organizer or ambassador'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/request-role')),
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.help_outline), title: const Text('Help & support'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/support')),
      ]),
    );
  }

  Future<void> _pickAvatar(BuildContext context, WidgetRef ref, String uid) async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 80);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      final ref0 = FirebaseStorage.instance.ref('avatars/$uid/avatar.jpg');
      await ref0.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await ref0.getDownloadURL();
      await ref.read(firestoreProvider).collection(Col.users).doc(uid).update({'avatarUrl': url});
      if (context.mounted) showCbSnack(context, 'Photo updated.');
    } catch (e) {
      if (context.mounted) showCbError(context, e);
    }
  }

  Future<void> _editTribes(BuildContext context, WidgetRef ref, UserProfile me) async {
    final tribes = ref.read(tribesProvider).value ?? const <Tribe>[];
    final selected = {...me.tribeIds};
    String? primary = me.primaryTribeId;
    await showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Your Tribes (pick 3+)', style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 8),
        Flexible(child: ListView(shrinkWrap: true, children: [for (final tr in tribes) CheckboxListTile(value: selected.contains(tr.id), onChanged: (v) => setState(() { v == true ? selected.add(tr.id) : selected.remove(tr.id); if (!selected.contains(primary)) primary = selected.firstOrNull; }), title: Text('${tr.emoji} ${tr.name}'), secondary: selected.contains(tr.id) ? IconButton(onPressed: () => setState(() => primary = tr.id), icon: Icon(primary == tr.id ? Icons.star : Icons.star_border, color: primary == tr.id ? CbColors.lime : null)) : null)])),
        FilledButton(onPressed: selected.length < 3 ? null : () async { await ref.read(firestoreProvider).collection(Col.users).doc(me.uid).update({'tribeIds': selected.toList(), 'primaryTribeId': primary}); if (ctx.mounted) Navigator.pop(ctx); }, child: const Text('Save')),
      ])))),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(userProfileProvider).value;
    final campus = ref.watch(campusProvider).value;
    final name = TextEditingController(text: me?.displayName ?? '');
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: name, decoration: InputDecoration(labelText: 'Display name', suffixIcon: IconButton(icon: const Icon(Icons.check), onPressed: () async { if (name.text.trim().length < 2 || me == null) return; await ref.read(firestoreProvider).collection(Col.users).doc(me.uid).update({'displayName': name.text.trim()}); if (context.mounted) showCbSnack(context, 'Name updated.'); }))),
        const SizedBox(height: 8),
        ListTile(leading: const Icon(Icons.notifications_outlined), title: const Text('Notifications'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/settings/notifications')),
        ListTile(leading: const Icon(Icons.lock_outline), title: const Text('Privacy'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/settings/privacy')),
        ListTile(leading: const Icon(Icons.download_outlined), title: const Text('Your data'), subtitle: const Text('Export or delete your account'), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/settings/data')),
        const Divider(),
        ListTile(leading: const Icon(Icons.description_outlined), title: const Text('Terms of Service'), onTap: () => launchUrl(Uri.parse(campus?.termsUrl ?? 'https://campusbuzz.app/terms'), mode: LaunchMode.externalApplication)),
        ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacy Policy'), onTap: () => launchUrl(Uri.parse(campus?.privacyPolicyUrl ?? 'https://campusbuzz.app/privacy'), mode: LaunchMode.externalApplication)),
        const Divider(),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Sign out'), onTap: () => ref.read(firebaseAuthProvider).signOut()),
        const SizedBox(height: 12),
        Text('Signed in as ${me?.email ?? ''}', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
      ]),
    );
  }
}

class NotificationPrefsScreen extends ConsumerWidget {
  const NotificationPrefsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(userProfileProvider).value;
    final cap = ref.watch(economyProvider).engagementNotificationCapPerDay;
    Future<void> set(String key, bool v) => ref.read(firestoreProvider).collection(Col.users).doc(me!.uid).update({'notificationPrefs.$key': v});
    final p = me?.notificationPrefs ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(children: [
        SwitchListTile(title: const Text('Event reminders'), subtitle: const Text('24h and 1h before events you RSVP to'), value: p['reminders'] ?? true, onChanged: (v) => set('reminders', v)),
        SwitchListTile(title: const Text('Tribe picks, rewards & streaks'), subtitle: Text('Never more than $cap a day'), value: p['engagement'] ?? true, onChanged: (v) => set('engagement', v)),
        SwitchListTile(title: const Text('Post-event feedback'), subtitle: const Text('A quick rating request ~2h after you check in'), value: p['postEvent'] ?? true, onChanged: (v) => set('postEvent', v)),
        const ListTile(title: Text('Cancellations, changes & security alerts'), subtitle: Text('Always on — these are about events you\'re attending or your account.'), trailing: Icon(Icons.lock_outline)),
      ]),
    );
  }
}

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(userProfileProvider).value;
    final talent = ref.watch(flagProvider(FeatureFlag.talentProfileEnabled));
    Future<void> set(String key, bool v) => ref.read(firestoreProvider).collection(Col.users).doc(me!.uid).update({'privacy.$key': v});
    final p = me?.privacy ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(children: [
        SwitchListTile(title: const Text('Show my activity to friends'), subtitle: const Text('Friends can see events you RSVP to or attend. Off by default.'), value: p['showActivityToFriends'] ?? false, onChanged: (v) => set('showActivityToFriends', v)),
        SwitchListTile(title: const Text('Post reviews anonymously by default'), value: p['anonymousFeedback'] ?? false, onChanged: (v) => set('anonymousFeedback', v)),
        if (talent) SwitchListTile(title: const Text('Participation profile (opt-in)'), subtitle: const Text('Lets you share a verified participation record externally in future. Private until you turn it on.'), value: p['talentProfileOptIn'] ?? false, onChanged: (v) => set('talentProfileOptIn', v)),
        const Padding(padding: EdgeInsets.all(16), child: Text('What we hold: name, college email, Tribes, event RSVPs and check-ins, BuzzCoin activity. Brands only see aggregate numbers. We never ask for Aadhaar, bank details or anything sensitive.')),
      ]),
    );
  }
}

class DataControlsScreen extends ConsumerStatefulWidget {
  const DataControlsScreen({super.key});
  @override
  ConsumerState<DataControlsScreen> createState() => _DataControlsScreenState();
}

class _DataControlsScreenState extends ConsumerState<DataControlsScreen> {
  bool _busy = false;
  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(functionsProvider).call('exportMyData');
      final json = r['json'] as String;
      await SharePlus.instance.share(ShareParams(text: json.length > 100000 ? json.substring(0, 100000) : json, subject: 'My CampusBuzz data export', title: 'campusbuzz-export.json'));
      if (mounted) showCbSnack(context, 'Export ready${r['storagePath'] != null ? ' (also saved to your private storage)' : ''}.');
    } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _delete() async {
    final typed = await askReason(context, title: 'Delete your account?', hint: 'Type DELETE to confirm. This removes your profile and anonymises your participation history.', confirmLabel: 'Delete forever');
    if (typed != 'DELETE') return;
    setState(() => _busy = true);
    try { await ref.read(functionsProvider).call('deleteMyAccount', {'confirm': 'DELETE'}); await ref.read(firebaseAuthProvider).signOut(); } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Your data')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Export', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('Get a JSON copy of everything CampusBuzz holds about you. Instant — well inside our 7-business-day commitment.'),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: _busy ? null : _export, icon: const Icon(Icons.download), label: const Text('Export my data')),
          const SizedBox(height: 28),
          Text('Delete account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          const Text('Removes your profile, email, Tribes and friendships; anonymises reviews; cancels upcoming RSVPs. Campus totals stay accurate but nothing identifies you. Unspent BuzzCoins are forfeited.'),
          const SizedBox(height: 10),
          OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: CbColors.danger, side: const BorderSide(color: CbColors.danger)), onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_forever), label: const Text('Delete my account')),
        ]),
      );
}

final notificationInboxProvider = StreamProvider<List<NotificationLog>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.notificationDeliveryLogs).where('uid', isEqualTo: uid).orderBy('at', descending: true).limit(50).snapshots().map((s) => s.docs.map(NotificationLog.fromDoc).where((n) => n.status == 'sent').toList());
});

class NotificationInboxScreen extends ConsumerWidget {
  const NotificationInboxScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationInboxProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications'), actions: [IconButton(onPressed: () => context.push('/settings/notifications'), icon: const Icon(Icons.tune))]),
      body: items.when(
        loading: () => const CbSkeletonList(height: 64),
        error: (e, _) => CbErrorView(error: e),
        data: (list) => list.isEmpty ? const CbEmpty(icon: Icons.notifications_none, title: 'Nothing yet', message: 'Reminders and updates for your events show up here.') : ListView.separated(itemCount: list.length, separatorBuilder: (_, __) => const Divider(), itemBuilder: (_, i) => ListTile(leading: Icon(switch (list[i].category) { 'reminder' => Icons.alarm, 'post_event' => Icons.star_outline, 'engagement' => Icons.auto_awesome, _ => Icons.info_outline }), title: Text(list[i].title), subtitle: Text(list[i].at == null ? '' : Fmt.relative(list[i].at!)), onTap: list[i].route == null ? null : () => context.push(list[i].route!))),
      ),
    );
  }
}

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});
  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _msg = TextEditingController(); bool _busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Help & support')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('Check-in didn\'t register? Reward code not working? Tell campus operations. Include the event name if it\'s about an event.'),
          const SizedBox(height: 12),
          TextField(controller: _msg, maxLines: 5, maxLength: 2000, decoration: const InputDecoration(hintText: 'What happened?')),
          const SizedBox(height: 12),
          FilledButton(onPressed: _busy ? null : () async {
            if (_msg.text.trim().isEmpty) return;
            setState(() => _busy = true);
            try {
              final me = ref.read(userProfileProvider).value;
              await ref.read(firestoreProvider).collection(Col.supportRequests).add({'uid': me?.uid, 'campusId': me?.activeCampusId, 'message': _msg.text.trim(), 'status': 'open', 'createdAt': FieldValue.serverTimestamp()});
              if (mounted) { showCbSnack(context, 'Sent. Campus ops usually replies within a day.'); context.pop(); }
            } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
          }, child: const Text('Send')),
        ]),
      );
}

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(userProfileProvider).value;
    final economy = ref.watch(economyProvider);
    final refs = ref.watch(_myReferralsProvider).value ?? const <Referral>[];
    final t = Theme.of(context).textTheme;
    final code = me?.referralCode ?? '';
    final link = DeepLinkService.referralUrl(code);
    return Scaffold(
      appBar: AppBar(title: const Text('Invite friends')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Bring a friend. Earn +${economy.referralReward} when they show up.', style: t.headlineSmall),
        const SizedBox(height: 8),
        Text('Not for signing up — only when they check in to their first event. Real participation, real reward.', style: t.bodyMedium),
        const SizedBox(height: 20),
        CbCard(gradient: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Your code', style: t.labelMedium), Text(code, style: t.displaySmall?.copyWith(letterSpacing: 3)), const SizedBox(height: 6), SelectableText(link, style: t.bodySmall)])),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: () { ref.read(analyticsProvider).track('referral_shared', {'source': 'referral_screen'}); SharePlus.instance.share(ShareParams(text: 'Join me on CampusBuzz — every event on campus, verified check-ins, real rewards. Use my code $code: $link')); }, icon: const Icon(Icons.ios_share), label: const Text('Share link'))),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () { Clipboard.setData(ClipboardData(text: code)); showCbSnack(context, 'Copied'); }, child: const Icon(Icons.copy)),
        ]),
        const SizedBox(height: 24),
        Text('Your referrals (${refs.length})', style: t.titleLarge),
        for (final r in refs) ListTile(contentPadding: EdgeInsets.zero, leading: Icon(r.rewardAwarded ? Icons.verified : Icons.hourglass_empty, color: r.rewardAwarded ? CbColors.success : CbColors.textTertiary), title: Text(r.rewardAwarded ? 'Attended · +${economy.referralReward}' : 'Joined · not attended yet'), subtitle: Text(r.signupAt == null ? '' : Fmt.relative(r.signupAt!))),
      ]),
    );
  }
}

final _myReferralsProvider = StreamProvider<List<Referral>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.referrals).where('referrerUid', isEqualTo: uid).orderBy('signupAt', descending: true).limit(100).snapshots().map((s) => s.docs.map(Referral.fromDoc).toList());
});

class ParticipationHistoryScreen extends ConsumerWidget {
  const ParticipationHistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkins = ref.watch(myCheckinsProvider);
    final rsvps = ref.watch(myUpcomingRsvpsProvider).value ?? const <Rsvp>[];
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Participation')),
      body: checkins.when(
        loading: () => const CbSkeletonList(height: 72),
        error: (e, _) => CbErrorView(error: e),
        data: (list) => ListView(padding: const EdgeInsets.all(16), children: [
          if (rsvps.isNotEmpty) ...[Text('Upcoming', style: t.titleLarge), for (final r in rsvps) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.event), title: Text(r.eventTitle), subtitle: Text(r.startAt == null ? '' : Fmt.dateTime(r.startAt!, tz)), trailing: Text(r.status == 'waitlisted' ? 'Waitlist' : 'Going', style: t.labelSmall), onTap: () => context.push('/events/${r.eventId}')), const SizedBox(height: 12)],
          Text('Verified attendance (${list.length})', style: t.titleLarge),
          if (list.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: CbEmpty(icon: Icons.qr_code_2, title: 'No check-ins yet', message: 'Scan the organizer\'s QR at your next event.')),
          for (final c in list) ListTile(contentPadding: EdgeInsets.zero, leading: Icon(c.method == 'manual' ? Icons.how_to_reg : Icons.verified, color: CbColors.success), title: Text(c.eventTitle), subtitle: Text('${Fmt.dateTime(c.at, tz)} · ${c.method == 'manual' ? 'manual' : 'QR'}${c.multiplierApplied ? ' · 2x streak' : ''}'), trailing: c.certificateRef != null ? TextButton(onPressed: () => context.push('/events/${c.eventId}/certificate'), child: const Text('Certificate')) : CbCoinBadge(amount: c.coinsAwarded), onTap: () => context.push('/events/${c.eventId}')),
        ]),
      ),
    );
  }
}

/// Participation certificate — only for verified check-ins (server-recorded), with a verification reference.
class CertificateScreen extends ConsumerWidget {
  const CertificateScreen({super.key, required this.eventId});
  final String eventId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checkin = ref.watch(myCheckinProvider(eventId)).value;
    final event = ref.watch(eventProvider(eventId)).value;
    final me = ref.watch(userProfileProvider).value;
    final campus = ref.watch(campusProvider).value;
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    if (checkin == null || event == null || me == null) return Scaffold(appBar: AppBar(title: const Text('Certificate')), body: const CbEmpty(icon: Icons.workspace_premium_outlined, title: 'No verified attendance', message: 'Certificates are only issued for verified check-ins.'));
    if (!event.certificateEnabled) return Scaffold(appBar: AppBar(title: const Text('Certificate')), body: const CbEmpty(title: 'Not available for this event'));
    Future<Uint8List> build(PdfPageFormat f) async {
      final doc = pw.Document();
      doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4.landscape, build: (ctx) => pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColor.fromHex('#FF5F1F'), width: 6)),
        padding: const pw.EdgeInsets.all(40),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('CampusBuzz', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#FF5F1F'))),
          pw.SizedBox(height: 30),
          pw.Text('Certificate of Participation', style: pw.TextStyle(fontSize: 34, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 24),
          pw.Text('This certifies that', style: const pw.TextStyle(fontSize: 14)),
          pw.Text(me.displayName, style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text('attended (verified check-in)', style: const pw.TextStyle(fontSize: 14)),
          pw.Text(event.title, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.Text('organised by ${event.clubName} · ${campus?.name ?? event.campusId}', style: const pw.TextStyle(fontSize: 14)),
          pw.Text(Fmt.longDate(event.startAt, tz), style: const pw.TextStyle(fontSize: 14)),
          pw.Spacer(),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Verification ref: ${checkin.certificateRef}', style: const pw.TextStyle(fontSize: 10)), pw.Text('Checked in ${Fmt.dateTime(checkin.at, tz)} via ${checkin.method == 'manual' ? 'organizer' : 'QR'}', style: const pw.TextStyle(fontSize: 10))]),
        ]),
      )));
      return doc.save();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Certificate')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        CbCard(gradient: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Certificate of Participation', style: t.headlineSmall),
          const SizedBox(height: 8),
          CbKeyValue('Student', me.displayName), CbKeyValue('Event', event.title), CbKeyValue('Organizer', event.clubName), CbKeyValue('Date', Fmt.longDate(event.startAt, tz)), CbKeyValue('Campus', campus?.name ?? event.campusId), CbKeyValue('Verification', checkin.certificateRef ?? '—'),
        ])),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: () async { final bytes = await build(PdfPageFormat.a4); await Printing.sharePdf(bytes: bytes, filename: 'campusbuzz-certificate-${event.id}.pdf'); }, icon: const Icon(Icons.picture_as_pdf), label: const Text('Download / share PDF')),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: () => Printing.layoutPdf(onLayout: build), icon: const Icon(Icons.print), label: const Text('Print')),
      ]),
    );
  }
}

class RequestRoleScreen extends ConsumerStatefulWidget {
  const RequestRoleScreen({super.key});
  @override
  ConsumerState<RequestRoleScreen> createState() => _RequestRoleScreenState();
}

class _RequestRoleScreenState extends ConsumerState<RequestRoleScreen> {
  String _role = 'organizer'; final _club = TextEditingController(), _note = TextEditingController(); bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final m = ref.watch(membershipProvider).value;
    final pending = m?.requestedRoles ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Request access')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Organizer and ambassador access is approved by campus operations — nobody can grant it to themselves.'),
        const SizedBox(height: 16),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'organizer', label: Text('Organizer')), ButtonSegment(value: 'ambassador', label: Text('Ambassador'))], selected: {_role}, onSelectionChanged: (s) => setState(() => _role = s.first)),
        const SizedBox(height: 12),
        if (_role == 'organizer') TextField(controller: _club, decoration: const InputDecoration(labelText: 'Club / committee')),
        const SizedBox(height: 12),
        TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'Why you? (role, what you run)')),
        const SizedBox(height: 16),
        if (pending.contains(_role)) const CbStatusPill(label: 'Request pending review', color: CbColors.warning, icon: Icons.hourglass_top)
        else FilledButton(onPressed: _busy ? null : () async { setState(() => _busy = true); try { await ref.read(functionsProvider).call('requestRole', {'campusId': m?.campusId, 'role': _role, 'clubName': _club.text.trim(), 'note': _note.text.trim()}); if (mounted) showCbSnack(context, 'Request sent to campus operations.'); } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); } }, child: const Text('Send request')),
      ]),
    );
  }
}

String prettyJson(Object o) => const JsonEncoder.withIndent('  ').convert(o);
