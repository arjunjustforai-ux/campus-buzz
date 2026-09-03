import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/models/models.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';

final friendshipsProvider = StreamProvider<List<Friendship>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.friendships).where('uids', arrayContains: uid).snapshots().map((s) => s.docs.map(Friendship.fromDoc).toList());
});

final userNameProvider = FutureProvider.family<String, String>((ref, uid) async {
  final s = await ref.watch(firestoreProvider).collection(Col.users).doc(uid).get();
  return s.data()?['displayName'] as String? ?? 'Student';
});

/// Lightweight friends: requests, accept/decline, unfriend/block, campus search. No chat.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});
  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _search = TextEditingController(); List<Membership> _results = const []; bool _searching = false;

  Future<void> _find() async {
    final q = _search.text.trim().toLowerCase();
    final campusId = ref.read(activeCampusIdProvider);
    if (q.length < 2 || campusId == null) return;
    setState(() => _searching = true);
    try {
      final s = await ref.read(firestoreProvider).collection(Col.memberships).where('campusId', isEqualTo: campusId).where('status', isEqualTo: 'active').limit(300).get();
      setState(() => _results = s.docs.map(Membership.fromDoc).where((m) => m.displayName.toLowerCase().contains(q) && m.uid != ref.read(currentUidProvider)).take(20).toList());
    } catch (e) {
      if (mounted) showCbError(context, e);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _call(String fn, Map<String, dynamic> data, String ok) async {
    try { await ref.read(functionsProvider).call(fn, data); if (mounted) showCbSnack(context, ok); } catch (e) { if (mounted) showCbError(context, e); }
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(flagProvider(FeatureFlag.friendsEnabled));
    final me = ref.watch(currentUidProvider) ?? '';
    final fs = ref.watch(friendshipsProvider).value ?? const <Friendship>[];
    final t = Theme.of(context).textTheme;
    if (!on) return Scaffold(appBar: AppBar(title: const Text('Friends')), body: const CbEmpty(icon: Icons.people_outline, title: 'Friends launch soon'));
    final incoming = fs.where((f) => f.status == 'pending' && f.requesterUid != me).toList();
    final outgoing = fs.where((f) => f.status == 'pending' && f.requesterUid == me).toList();
    final accepted = fs.where((f) => f.status == 'accepted').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(controller: _search, onSubmitted: (_) => _find(), decoration: InputDecoration(hintText: 'Find someone on your campus', prefixIcon: const Icon(Icons.search), suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null)),
        for (final m in _results) ListTile(leading: CbAvatar(name: m.displayName), title: Text(m.displayName), trailing: TextButton(onPressed: () => _call('sendFriendRequest', {'uid': m.uid}, 'Request sent.'), child: const Text('Add'))),
        if (incoming.isNotEmpty) ...[const SizedBox(height: 16), Text('Requests', style: t.titleLarge)],
        for (final f in incoming) _FriendTile(uid: f.other(me), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(tooltip: 'Accept', onPressed: () => _call('respondFriendRequest', {'uid': f.other(me), 'accept': true}, 'Friends!'), icon: const Icon(Icons.check, color: CbColors.success)), IconButton(tooltip: 'Decline', onPressed: () => _call('respondFriendRequest', {'uid': f.other(me), 'accept': false}, 'Declined.'), icon: const Icon(Icons.close, color: CbColors.danger))])),
        const SizedBox(height: 16),
        Text('Friends (${accepted.length})', style: t.titleLarge),
        if (accepted.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: CbEmpty(icon: Icons.people_outline, title: 'No friends yet', message: 'Add people to see which events they\'re going to — if they\'ve opted in.')),
        for (final f in accepted) _FriendTile(uid: f.other(me), trailing: PopupMenuButton<String>(onSelected: (v) async { if (v == 'remove' && await confirm(context, title: 'Remove friend?')) _call('removeFriend', {'uid': f.other(me)}, 'Removed.'); if (v == 'block' && await confirm(context, title: 'Block this student?', message: "They won't be able to send you requests.", destructive: true)) _call('removeFriend', {'uid': f.other(me), 'block': true}, 'Blocked.'); }, itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove')), PopupMenuItem(value: 'block', child: Text('Block'))])),
        if (outgoing.isNotEmpty) ...[const SizedBox(height: 16), Text('Sent', style: t.titleLarge)],
        for (final f in outgoing) _FriendTile(uid: f.other(me), trailing: Text('Pending', style: t.labelSmall)),
      ]),
    );
  }
}

class _FriendTile extends ConsumerWidget {
  const _FriendTile({required this.uid, required this.trailing});
  final String uid; final Widget trailing;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(userNameProvider(uid)).value ?? '…';
    return ListTile(contentPadding: EdgeInsets.zero, leading: CbAvatar(name: name), title: Text(name), trailing: trailing);
  }
}
