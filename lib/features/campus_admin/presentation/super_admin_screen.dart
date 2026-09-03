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

final _campusesProvider = StreamProvider<List<Campus>>((ref) => ref.watch(firestoreProvider).collection(Col.campuses).snapshots().map((s) => s.docs.map(Campus.fromDoc).toList()));
final _brandsProvider = StreamProvider<List<BrandAccount>>((ref) => ref.watch(firestoreProvider).collection(Col.brandAccounts).snapshots().map((s) => s.docs.map(BrandAccount.fromDoc).toList()));
final _entitlementsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) => ref.watch(firestoreProvider).collection(Col.entitlements).snapshots().map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList()));
final _platformAuditProvider = StreamProvider<List<AuditLog>>((ref) => ref.watch(firestoreProvider).collection(Col.auditLogs).orderBy('at', descending: true).limit(50).snapshots().map((s) => s.docs.map(AuditLog.fromDoc).toList()));

Future<void> _call(BuildContext context, WidgetRef ref, String fn, Map<String, dynamic> data, String ok) async {
  try { await ref.read(functionsProvider).call(fn, data); if (context.mounted) showCbSnack(context, ok); } catch (e) { if (context.mounted) showCbError(context, e); }
}

/// Platform-level: provision campuses, manage domains, aggregate metrics, audit.
class SuperCampusesScreen extends ConsumerWidget {
  const SuperCampusesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campuses = ref.watch(_campusesProvider);
    final audit = ref.watch(_platformAuditProvider).value ?? const <AuditLog>[];
    final t = Theme.of(context).textTheme;
    return CbPage(
      title: 'Campuses',
      subtitle: 'Provisioning is the only way a campus is created. Seed data never touches production.',
      actions: [FilledButton.icon(onPressed: () => _dialog(context, ref), icon: const Icon(Icons.add), label: const Text('Provision campus'))],
      child: campuses.when(
        loading: () => const CbSkeletonList(),
        error: (e, _) => CbErrorView(error: e),
        data: (list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final c in list) CbCard(child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(c.name, style: t.titleMedium), Text('${c.id} · ${c.domains.join(', ')} · ${c.timezone} · economy v${c.economy.version}', style: t.bodySmall)])),
            CbStatusPill(label: c.status, color: c.status == 'active' ? CbColors.success : CbColors.textTertiary),
            IconButton(onPressed: () => _dialog(context, ref, campus: c), icon: const Icon(Icons.edit_outlined)),
            TextButton(onPressed: () => _call(context, ref, 'setActiveCampus', {'campusId': c.id}, 'Switched context to ${c.name}.'), child: const Text('Switch to')),
          ])),
          const SizedBox(height: 20),
          Text('Platform audit (latest 50)', style: t.titleLarge),
          for (final a in audit) ListTile(dense: true, contentPadding: EdgeInsets.zero, title: Text(a.action), subtitle: Text('${a.entityType} ${a.entityId} · ${a.actorUid.substring(0, a.actorUid.length.clamp(0, 10))}'), trailing: Text(a.at == null ? '' : Fmt.relative(a.at!), style: t.labelSmall)),
        ]),
      ),
    );
  }

  Future<void> _dialog(BuildContext context, WidgetRef ref, {Campus? campus}) async {
    final id = TextEditingController(text: campus?.id ?? ''), name = TextEditingController(text: campus?.name ?? ''), short = TextEditingController(text: campus?.shortName ?? ''), domains = TextEditingController(text: campus?.domains.join(', ') ?? ''), tz = TextEditingController(text: campus?.timezone ?? 'Asia/Kolkata'), city = TextEditingController(text: campus?.city ?? ''), admin = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(campus == null ? 'Provision campus' : 'Edit campus'), content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: id, enabled: campus == null, decoration: const InputDecoration(labelText: 'Campus id (slug)')), TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), TextField(controller: short, decoration: const InputDecoration(labelText: 'Short name')), TextField(controller: domains, decoration: const InputDecoration(labelText: 'Email domains (comma separated)')), TextField(controller: tz, decoration: const InputDecoration(labelText: 'Timezone')), TextField(controller: city, decoration: const InputDecoration(labelText: 'City')), TextField(controller: admin, decoration: const InputDecoration(labelText: 'First campus admin uid (optional)'))])), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))]));
    if (ok == true && context.mounted) _call(context, ref, 'provisionCampus', {'campusId': id.text.trim(), 'name': name.text.trim(), 'shortName': short.text.trim(), 'domains': domains.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(), 'timezone': tz.text.trim(), 'city': city.text.trim(), 'adminUid': admin.text.trim()}, 'Campus saved.');
  }
}

class SuperBrandsScreen extends ConsumerWidget {
  const SuperBrandsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brands = ref.watch(_brandsProvider);
    return CbPage(
      title: 'Brand accounts',
      actions: [FilledButton.icon(onPressed: () => _dialog(context, ref), icon: const Icon(Icons.add), label: const Text('New brand'))],
      child: brands.when(loading: () => const CbSkeletonList(), error: (e, _) => CbErrorView(error: e), data: (list) => Column(children: [for (final b in list) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.storefront_outlined), title: Text(b.name, style: Theme.of(context).textTheme.titleMedium), subtitle: Text('${b.id} · ${b.status}'), trailing: TextButton(onPressed: () => _dialog(context, ref, brand: b), child: const Text('Add member / edit')))])),
    );
  }

  Future<void> _dialog(BuildContext context, WidgetRef ref, {BrandAccount? brand}) async {
    final name = TextEditingController(text: brand?.name ?? ''), members = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text(brand == null ? 'New brand' : brand.name), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Brand name')), TextField(controller: members, decoration: const InputDecoration(labelText: 'Member uids to add (comma separated)'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))]));
    if (ok == true && context.mounted) _call(context, ref, 'upsertBrandAccount', {'brandId': brand?.id, 'name': name.text.trim(), 'memberUids': members.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()}, 'Brand saved.');
  }
}

class SuperEntitlementsScreen extends ConsumerWidget {
  const SuperEntitlementsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ents = ref.watch(_entitlementsProvider);
    return CbPage(
      title: 'Entitlements',
      subtitle: 'Commercial packaging without redeploys: organizer_premium (clubs), campus_analytics (campuses), brand_dashboard (brands). No payment gateway — billing status is recorded manually.',
      actions: [FilledButton.icon(onPressed: () => _dialog(context, ref), icon: const Icon(Icons.add), label: const Text('Grant'))],
      child: ents.when(loading: () => const CbSkeletonList(), error: (e, _) => CbErrorView(error: e), data: (list) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [DataColumn(label: Text('Subject')), DataColumn(label: Text('Key')), DataColumn(label: Text('Plan')), DataColumn(label: Text('Billing')), DataColumn(label: Text('Status')), DataColumn(label: Text('Valid until')), DataColumn(label: Text(''))], rows: [for (final e in list) DataRow(cells: [DataCell(Text('${e['subjectType']}:${e['subjectId']}')), DataCell(Text('${e['key']}')), DataCell(Text('${e['plan'] ?? '—'}')), DataCell(Text('${e['billingStatus']}')), DataCell(CbStatusPill(label: '${e['status']}', color: e['status'] == 'active' ? CbColors.success : CbColors.textTertiary)), DataCell(Text(e['validUntil'] == null ? '∞' : Fmt.date(Fmt.toDate(e['validUntil'])!, 'Asia/Kolkata'))), DataCell(TextButton(onPressed: () => _call(context, ref, 'setEntitlement', {'subjectType': e['subjectType'], 'subjectId': e['subjectId'], 'key': e['key'], 'status': e['status'] == 'active' ? 'inactive' : 'active', 'reason': 'Toggled from platform console'}, 'Updated.'), child: Text(e['status'] == 'active' ? 'Deactivate' : 'Activate')))])]))),
    );
  }

  Future<void> _dialog(BuildContext context, WidgetRef ref) async {
    var type = 'club'; var key = 'organizer_premium'; final id = TextEditingController(), plan = TextEditingController(text: 'manual'), billing = TextEditingController(text: 'manual');
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(title: const Text('Grant entitlement'), content: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Subject type'), items: const [DropdownMenuItem(value: 'club', child: Text('Club')), DropdownMenuItem(value: 'campus', child: Text('Campus')), DropdownMenuItem(value: 'brand', child: Text('Brand'))], onChanged: (v) => setState(() { type = v!; key = switch (type) { 'club' => 'organizer_premium', 'campus' => 'campus_analytics', _ => 'brand_dashboard' }; })), TextField(controller: id, decoration: const InputDecoration(labelText: 'Subject id')), DropdownButtonFormField<String>(initialValue: key, decoration: const InputDecoration(labelText: 'Entitlement'), items: const [DropdownMenuItem(value: 'organizer_basic', child: Text('organizer_basic')), DropdownMenuItem(value: 'organizer_premium', child: Text('organizer_premium (₹2,000/mo assumption — configurable)')), DropdownMenuItem(value: 'campus_analytics', child: Text('campus_analytics (semester licence)')), DropdownMenuItem(value: 'brand_dashboard', child: Text('brand_dashboard'))], onChanged: (v) => setState(() => key = v!)), TextField(controller: plan, decoration: const InputDecoration(labelText: 'Plan label')), TextField(controller: billing, decoration: const InputDecoration(labelText: 'Billing status'))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Grant'))])));
    if (ok == true && context.mounted) _call(context, ref, 'setEntitlement', {'subjectType': type, 'subjectId': id.text.trim(), 'key': key, 'status': 'active', 'plan': plan.text.trim(), 'billingStatus': billing.text.trim(), 'reason': 'Granted from platform console'}, 'Entitlement granted (audited).');
  }
}
