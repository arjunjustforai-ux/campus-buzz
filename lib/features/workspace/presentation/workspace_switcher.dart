import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/models/models.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';

/// Lets multi-role users move between authorised workspaces without logging out.
class Workspace {
  const Workspace(this.label, this.path, this.icon);
  final String label, path; final IconData icon;
}

final workspacesProvider = Provider<List<Workspace>>((ref) {
  final roles = ref.watch(rolesProvider);
  final brands = ref.watch(brandMembershipsProvider).value ?? const [];
  return [
    const Workspace('Student', '/home', Icons.school_outlined),
    if (roles.contains(Role.organizer) || roles.contains(Role.campusAdmin)) const Workspace('Organizer', '/organizer', Icons.event_available_outlined),
    if (roles.contains(Role.ambassador)) const Workspace('Ambassador', '/ambassador', Icons.campaign_outlined),
    if (roles.contains(Role.campusAdmin)) const Workspace('Campus Ops', '/admin', Icons.dashboard_outlined),
    if (brands.isNotEmpty || roles.contains(Role.brand)) const Workspace('Brand', '/brand', Icons.storefront_outlined),
    if (roles.contains(Role.vendor)) const Workspace('Redemption partner', '/vendor', Icons.point_of_sale_outlined),
    if (roles.contains(Role.superAdmin)) const Workspace('Platform', '/super', Icons.admin_panel_settings_outlined),
  ];
});

class WorkspaceSwitcherButton extends ConsumerWidget {
  const WorkspaceSwitcherButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspacesProvider);
    final memberships = ref.watch(allMembershipsProvider).value ?? const [];
    if (ws.length <= 1 && memberships.length <= 1) return const SizedBox.shrink();
    return IconButton(tooltip: 'Switch workspace', icon: const Icon(Icons.swap_horiz, color: CbColors.limeText), onPressed: () => showWorkspaceSheet(context, ref));
  }
}

Future<void> showWorkspaceSheet(BuildContext context, WidgetRef ref) async {
  final ws = ref.read(workspacesProvider);
  final memberships = ref.read(allMembershipsProvider).value ?? const [];
  final active = ref.read(activeCampusIdProvider);
  await showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: [
        Text('Workspaces', style: Theme.of(ctx).textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final w in ws) ListTile(leading: Icon(w.icon), title: Text(w.label), onTap: () { Navigator.pop(ctx); context.go(w.path); }),
        if (memberships.length > 1) ...[
          const Divider(),
          Text('Campus', style: Theme.of(ctx).textTheme.titleMedium),
          for (final m in memberships)
            ListTile(
              leading: Icon(m.campusId == active ? Icons.radio_button_checked : Icons.radio_button_off, color: m.campusId == active ? CbColors.limeText : null),
              title: Text(m.campusId),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(functionsProvider).call('setActiveCampus', {'campusId': m.campusId});
                  if (context.mounted) showCbSnack(context, 'Switched to ${m.campusId}');
                } catch (e) {
                  if (context.mounted) showCbError(context, e);
                }
              },
            ),
        ],
      ]),
    ),
  );
}
