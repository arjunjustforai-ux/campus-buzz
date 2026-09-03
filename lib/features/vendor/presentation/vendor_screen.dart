import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/models/models.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatting.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';

final vendorRedemptionsProvider = StreamProvider<List<Redemption>>((ref) {
  final m = ref.watch(membershipProvider).value;
  final vendorId = m?.vendorId;
  if (vendorId == null) return Stream.value(const []);
  return ref.watch(firestoreProvider).collection(Col.redemptions).where('vendorId', isEqualTo: vendorId).orderBy('issuedAt', descending: true).limit(200).snapshots().map((s) => s.docs.map(Redemption.fromDoc).toList());
});

final myVendorProvider = StreamProvider<Vendor?>((ref) {
  final vendorId = ref.watch(membershipProvider).value?.vendorId;
  if (vendorId == null) return Stream.value(null);
  return ref.watch(firestoreProvider).collection(Col.vendors).doc(vendorId).snapshots().map((s) => s.exists ? Vendor.fromDoc(s) : null);
});

/// Redemption partner: enter/scan a code → validate → fulfil.
class VendorRedeemScreen extends ConsumerStatefulWidget {
  const VendorRedeemScreen({super.key});
  @override
  ConsumerState<VendorRedeemScreen> createState() => _VendorRedeemScreenState();
}

class _VendorRedeemScreenState extends ConsumerState<VendorRedeemScreen> {
  final _code = TextEditingController(); Map<String, dynamic>? _validated; bool _busy = false;

  Future<void> _validate() async {
    setState(() { _busy = true; _validated = null; });
    try { _validated = await ref.read(functionsProvider).call('validateRedemption', {'code': _code.text.trim()}); } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _fulfil() async {
    setState(() => _busy = true);
    try { final r = await ref.read(functionsProvider).call('fulfillRedemption', {'code': _code.text.trim()}); if (mounted) { showCbSnack(context, r['status'] == 'already' ? 'Already fulfilled earlier.' : 'Fulfilled. Thanks!'); setState(() { _validated = null; _code.clear(); }); } } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final vendor = ref.watch(myVendorProvider).value;
    final recent = ref.watch(vendorRedemptionsProvider).value ?? const <Redemption>[];
    final tz = ref.watch(campusTimezoneProvider);
    final t = Theme.of(context).textTheme;
    final v = _validated;
    return CbPage(
      title: vendor?.name ?? 'Redeem',
      subtitle: 'Enter the student\'s code, validate, then mark it fulfilled.',
      maxWidth: 720,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: TextField(controller: _code, textCapitalization: TextCapitalization.characters, onSubmitted: (_) => _validate(), decoration: const InputDecoration(labelText: 'Redemption code', hintText: 'ABCD-1234'))),
          const SizedBox(width: 8),
          FilledButton(onPressed: _busy ? null : _validate, child: const Text('Validate')),
        ]),
        const SizedBox(height: 16),
        if (v != null)
          CbCard(borderColor: v['valid'] == true ? CbColors.lime : CbColors.danger, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(v['valid'] == true ? Icons.check_circle : Icons.error, color: v['valid'] == true ? CbColors.lime : CbColors.danger), const SizedBox(width: 8), Text(v['valid'] == true ? 'Valid — ready to fulfil' : 'Not valid (${v['status']})', style: t.titleMedium)]),
            const SizedBox(height: 8),
            CbKeyValue('Reward', '${v['rewardTitle']}'),
            if (v['faceValue'] != null) CbKeyValue('Face value', Fmt.rupees((v['faceValue'] as num))),
            if (v['issuedAt'] != null) CbKeyValue('Issued', Fmt.dateTime(DateTime.fromMillisecondsSinceEpoch((v['issuedAt'] as num).toInt(), isUtc: true), tz)),
            const SizedBox(height: 12),
            if (v['valid'] == true) FilledButton.icon(onPressed: _busy ? null : _fulfil, icon: const Icon(Icons.done_all), label: const Text('Mark fulfilled')),
          ])),
        const SizedBox(height: 24),
        Text('Recent redemptions', style: t.titleLarge),
        const SizedBox(height: 8),
        if (recent.isEmpty) const CbEmpty(icon: Icons.receipt_long, title: 'Nothing yet'),
        for (final r in recent.take(30)) ListTile(contentPadding: EdgeInsets.zero, leading: Icon(r.status == 'fulfilled' ? Icons.check_circle : Icons.confirmation_number_outlined, color: r.status == 'fulfilled' ? CbColors.success : CbColors.textTertiary), title: Text('${r.rewardTitle} · ${r.code}'), subtitle: Text('${r.status} · ${r.issuedAt == null ? '' : Fmt.dateTime(r.issuedAt!, tz)}'), trailing: r.faceValue != null ? Text(Fmt.rupees(r.faceValue!)) : null),
      ]),
    );
  }
}

class VendorSettlementScreen extends ConsumerWidget {
  const VendorSettlementScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendor = ref.watch(myVendorProvider).value;
    final all = ref.watch(vendorRedemptionsProvider).value ?? const <Redemption>[];
    final t = Theme.of(context).textTheme;
    final byMonth = <String, ({int count, num value, int pending})>{};
    for (final r in all.where((r) => r.status == 'fulfilled')) {
      final k = r.settlementMonth ?? 'unknown';
      final cur = byMonth[k] ?? (count: 0, value: 0, pending: 0);
      byMonth[k] = (count: cur.count + 1, value: cur.value + (r.faceValue ?? 0), pending: cur.pending + (r.settlementStatus == 'pending' ? 1 : 0));
    }
    final months = byMonth.keys.toList()..sort((a, b) => b.compareTo(a));
    return CbPage(
      title: 'Settlement',
      subtitle: vendor?.contact ?? '',
      maxWidth: 720,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CbStatGrid(minTileWidth: 160, children: [
          CbStat(label: 'Fulfilled (all-time)', value: '${vendor?.fulfilled ?? all.where((r) => r.status == 'fulfilled').length}', icon: Icons.done_all),
          CbStat(label: 'Pending settlement', value: Fmt.rupees(vendor?.pendingSettlementValue ?? 0), icon: Icons.account_balance_wallet_outlined, color: CbColors.warning),
        ]),
        const SizedBox(height: 16),
        Text('By month', style: t.titleLarge),
        const SizedBox(height: 8),
        if (months.isEmpty) const CbEmpty(icon: Icons.receipt_long, title: 'No fulfilled redemptions yet'),
        for (final m in months) ListTile(contentPadding: EdgeInsets.zero, title: Text(m), subtitle: Text('${byMonth[m]!.count} redemptions · ${byMonth[m]!.pending} pending'), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [Text(Fmt.rupees(byMonth[m]!.value), style: t.titleMedium), CbStatusPill(label: byMonth[m]!.pending == 0 ? 'Settled' : 'Pending', color: byMonth[m]!.pending == 0 ? CbColors.success : CbColors.warning)])),
        const SizedBox(height: 12),
        Text('Campus operations marks months as settled after reconciliation. This is an operational record, not an invoice.', style: t.bodySmall),
      ]),
    );
  }
}
