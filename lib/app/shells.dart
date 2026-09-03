import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_providers.dart';
import '../core/models/models.dart';
import '../core/theme/app_colors.dart';
import '../features/workspace/presentation/workspace_switcher.dart';

/// Student mobile shell: Home · Explore · Scan · Rewards · Profile. Scan is prominent.
class StudentShell extends ConsumerWidget {
  const StudentShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: _Logo()),
            trailing: const Padding(padding: EdgeInsets.only(top: 24), child: WorkspaceSwitcherButton()),
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: Text('Home')),
              NavigationRailDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: Text('Explore')),
              NavigationRailDestination(icon: Icon(Icons.qr_code_scanner), label: Text('Scan')),
              NavigationRailDestination(icon: Icon(Icons.card_giftcard_outlined), selectedIcon: Icon(Icons.card_giftcard), label: Text('Rewards')),
              NavigationRailDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: Text('Profile')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: shell),
        ]),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          const NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Explore'),
          NavigationDestination(
            icon: Semantics(label: 'Scan event QR code to check in', child: Container(width: 44, height: 44, decoration: const BoxDecoration(gradient: CbColors.gradient, shape: BoxShape.circle), child: const Icon(Icons.qr_code_scanner, color: CbColors.dark))),
            label: 'Scan',
          ),
          const NavigationDestination(icon: Icon(Icons.card_giftcard_outlined), selectedIcon: Icon(Icons.card_giftcard), label: 'Rewards'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 40, decoration: const BoxDecoration(gradient: CbColors.gradient, borderRadius: BorderRadius.all(Radius.circular(12))), child: const Icon(Icons.bolt, color: CbColors.dark)),
        const SizedBox(height: 6),
        Text('CampusBuzz', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: CbColors.textPrimary)),
      ]);
}

/// Desktop-quality dashboard shell (organizer / admin / brand / vendor / super) with a
/// left navigation rail that collapses to a drawer on narrow screens.
class DashboardDestination {
  const DashboardDestination(this.path, this.label, this.icon, {this.selectedIcon});
  final String path, label; final IconData icon; final IconData? selectedIcon;
}

class DashboardShell extends ConsumerWidget {
  const DashboardShell({super.key, required this.title, required this.destinations, required this.child, this.requiredRoles = const {}});
  final String title; final List<DashboardDestination> destinations; final Widget child; final Set<Role> requiredRoles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(rolesProvider);
    final brands = ref.watch(brandMembershipsProvider).value ?? const [];
    final allowed = requiredRoles.isEmpty || requiredRoles.any(roles.contains) || (requiredRoles.contains(Role.brand) && brands.isNotEmpty);
    if (!allowed) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.lock_outline, size: 40, color: CbColors.warning),
          const SizedBox(height: 12),
          Text("You don't have access to this workspace.", style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Ask campus operations if you think you should.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          FilledButton(onPressed: () => context.go('/home'), child: const Text('Back to CampusBuzz')),
        ]))),
      );
    }
    final location = GoRouterState.of(context).uri.path;
    var selected = 0;
    for (var i = 0; i < destinations.length; i++) {
      final p = destinations[i].path;
      if (location == p || (location.startsWith('$p/') && p.split('/').length >= destinations[selected].path.split('/').length)) selected = i;
    }
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final rail = NavigationRail(
      extended: wide,
      minExtendedWidth: 220,
      selectedIndex: selected,
      onDestinationSelected: (i) => context.go(destinations[i].path),
      leading: Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Row(children: [Container(width: 32, height: 32, decoration: const BoxDecoration(gradient: CbColors.gradient, borderRadius: BorderRadius.all(Radius.circular(10))), child: const Icon(Icons.bolt, color: CbColors.dark, size: 20)), if (wide) ...[const SizedBox(width: 10), Text(title, style: Theme.of(context).textTheme.titleMedium)]])),
      trailing: Expanded(child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: const EdgeInsets.only(bottom: 16), child: Column(mainAxisSize: MainAxisSize.min, children: [const WorkspaceSwitcherButton(), TextButton.icon(onPressed: () => context.go('/home'), icon: const Icon(Icons.arrow_back, size: 16), label: wide ? const Text('Student app') : const SizedBox.shrink())])))),
      destinations: destinations.map((d) => NavigationRailDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon ?? d.icon), label: Text(d.label))).toList(),
    );
    if (MediaQuery.sizeOf(context).width < 700) {
      return Scaffold(
        appBar: AppBar(title: Text('$title · ${destinations[selected].label}')),
        drawer: Drawer(child: ListView(children: [
          DrawerHeader(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
          for (var i = 0; i < destinations.length; i++) ListTile(leading: Icon(destinations[i].icon), title: Text(destinations[i].label), selected: i == selected, onTap: () { Navigator.pop(context); context.go(destinations[i].path); }),
          const Divider(),
          const Padding(padding: EdgeInsets.all(8), child: WorkspaceSwitcherButton()),
          ListTile(leading: const Icon(Icons.arrow_back), title: const Text('Student app'), onTap: () => context.go('/home')),
        ])),
        body: child,
      );
    }
    return Scaffold(body: Row(children: [rail, const VerticalDivider(width: 1), Expanded(child: child)]));
  }
}
