import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/shells.dart';
import '../../features/ambassador/presentation/ambassador_screen.dart';
import '../../features/brands/presentation/brand_screens.dart';
import '../../features/campus_admin/presentation/admin_screens.dart';
import '../../features/checkin/presentation/scan_screen.dart';
import '../../features/events/presentation/event_detail_screen.dart';
import '../../features/feed/presentation/home_screen.dart';
import '../../features/friends/presentation/friends_screen.dart';
import '../../features/onboarding/presentation/auth_screens.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/organizer/presentation/organizer_screens.dart';
import '../../features/profile/presentation/profile_screens.dart';
import '../../features/quests/presentation/quest_screens.dart';
import '../../features/reviews/presentation/feedback_screen.dart';
import '../../features/rewards/presentation/rewards_screens.dart';
import '../../features/search/presentation/explore_screen.dart';
import '../../features/tribes/presentation/tribe_screens.dart';
import '../../features/vendor/presentation/vendor_screen.dart';
import '../../features/pilot/presentation/survey_screen.dart';
import '../../features/campus_admin/presentation/super_admin_screen.dart';
import '../auth/auth_providers.dart';
import '../models/models.dart';
import 'deep_links.dart';

/// Bridges Riverpod state into GoRouter's refreshListenable.
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(Ref ref) {
    ref.listen<AuthPhase>(authPhaseProvider, (_, __) => notifyListeners());
    ref.listen<Set<Role>>(rolesProvider, (_, __) => notifyListeners());
  }
}

final _rootKey = GlobalKey<NavigatorState>();

const _publicRoutes = {'/welcome', '/sign-in', '/register', '/forgot-password'};

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthNotifier(ref);
  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    refreshListenable: notifier,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final phase = ref.read(authPhaseProvider);
      final path = state.uri.path;
      // Shareable link aliases.
      if (path.startsWith('/e/')) return '/events/${path.substring(3)}';
      if (path.startsWith('/r/')) return '/register?ref=${path.substring(3)}';
      if (path.startsWith('/q/')) return '/quests/${path.substring(3)}';
      final isPublic = _publicRoutes.contains(path);
      switch (phase) {
        case AuthPhase.loading:
          return path == '/splash' ? null : '/splash?next=${Uri.encodeComponent(state.uri.toString())}';
        case AuthPhase.signedOut:
          return isPublic ? null : '/welcome';
        case AuthPhase.unverified:
          return path == '/verify-email' ? null : '/verify-email';
        case AuthPhase.needsOnboarding:
          return path == '/onboarding' ? null : '/onboarding';
        case AuthPhase.suspended:
          return path == '/suspended' ? null : '/suspended';
        case AuthPhase.ready:
          if (isPublic || path == '/verify-email' || path == '/onboarding' || path == '/suspended') return '/home';
          if (path == '/splash') {
            final next = state.uri.queryParameters['next'];
            return next != null && next.isNotEmpty && !next.startsWith('/splash') ? next : '/home';
          }
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (c, s) => const WelcomeScreen()),
      GoRoute(path: '/sign-in', builder: (c, s) => const SignInScreen()),
      GoRoute(path: '/register', builder: (c, s) => RegisterScreen(referralCode: s.uri.queryParameters['ref'])),
      GoRoute(path: '/forgot-password', builder: (c, s) => const ForgotPasswordScreen()),
      GoRoute(path: '/verify-email', builder: (c, s) => const VerifyEmailScreen()),
      GoRoute(path: '/onboarding', builder: (c, s) => const OnboardingScreen()),
      GoRoute(path: '/suspended', builder: (c, s) => const SuspendedScreen()),

      // Student shell -----------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => StudentShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (c, s) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/explore', builder: (c, s) => ExploreScreen(initialQuery: s.uri.queryParameters['q'], initialTribe: s.uri.queryParameters['tribe']))]),
          StatefulShellBranch(routes: [GoRoute(path: '/scan', builder: (c, s) => const ScanScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/rewards', builder: (c, s) => const RewardsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen())]),
        ],
      ),

      // Student detail routes (root navigator, full-screen) ------------------
      GoRoute(path: '/events/:id', parentNavigatorKey: _rootKey, builder: (c, s) => EventDetailScreen(eventId: s.pathParameters['id']!)),
      GoRoute(path: '/events/:id/feedback', parentNavigatorKey: _rootKey, builder: (c, s) => FeedbackScreen(eventId: s.pathParameters['id']!)),
      GoRoute(path: '/events/:id/certificate', parentNavigatorKey: _rootKey, builder: (c, s) => CertificateScreen(eventId: s.pathParameters['id']!)),
      GoRoute(path: '/rewards/redemptions/:id', parentNavigatorKey: _rootKey, builder: (c, s) => RedemptionDetailScreen(redemptionId: s.pathParameters['id']!)),
      GoRoute(path: '/rewards/:id', parentNavigatorKey: _rootKey, builder: (c, s) => RewardDetailScreen(rewardId: s.pathParameters['id']!)),
      GoRoute(path: '/wallet', parentNavigatorKey: _rootKey, builder: (c, s) => const WalletScreen()),
      GoRoute(path: '/tribes/leaderboard', parentNavigatorKey: _rootKey, builder: (c, s) => const LeaderboardScreen()),
      GoRoute(path: '/tribes/:id', parentNavigatorKey: _rootKey, builder: (c, s) => TribeScreen(tribeId: s.pathParameters['id']!)),
      GoRoute(path: '/friends', parentNavigatorKey: _rootKey, builder: (c, s) => const FriendsScreen()),
      GoRoute(path: '/quests', parentNavigatorKey: _rootKey, builder: (c, s) => const QuestsScreen()),
      GoRoute(path: '/quests/:id', parentNavigatorKey: _rootKey, builder: (c, s) => QuestDetailScreen(questId: s.pathParameters['id']!)),
      GoRoute(path: '/referrals', parentNavigatorKey: _rootKey, builder: (c, s) => const ReferralScreen()),
      GoRoute(path: '/history', parentNavigatorKey: _rootKey, builder: (c, s) => const ParticipationHistoryScreen()),
      GoRoute(path: '/settings', parentNavigatorKey: _rootKey, builder: (c, s) => const SettingsScreen()),
      GoRoute(path: '/settings/privacy', parentNavigatorKey: _rootKey, builder: (c, s) => const PrivacyScreen()),
      GoRoute(path: '/settings/notifications', parentNavigatorKey: _rootKey, builder: (c, s) => const NotificationPrefsScreen()),
      GoRoute(path: '/settings/data', parentNavigatorKey: _rootKey, builder: (c, s) => const DataControlsScreen()),
      GoRoute(path: '/notifications', parentNavigatorKey: _rootKey, builder: (c, s) => const NotificationInboxScreen()),
      GoRoute(path: '/support', parentNavigatorKey: _rootKey, builder: (c, s) => const SupportScreen()),
      GoRoute(path: '/surveys/:id', parentNavigatorKey: _rootKey, builder: (c, s) => SurveyScreen(surveyId: s.pathParameters['id']!)),
      GoRoute(path: '/request-role', parentNavigatorKey: _rootKey, builder: (c, s) => const RequestRoleScreen()),

      // Organizer workspace ----------------------------------------------
      ShellRoute(
        builder: (c, s, child) => DashboardShell(title: 'Organizer', requiredRoles: const {Role.organizer, Role.campusAdmin}, destinations: const [
          DashboardDestination('/organizer', 'Overview', Icons.dashboard_outlined),
          DashboardDestination('/organizer/events', 'Events', Icons.event_outlined),
          DashboardDestination('/organizer/events/new', 'Create event', Icons.add_circle_outline),
          DashboardDestination('/organizer/analytics', 'Analytics', Icons.insights_outlined),
        ], child: child),
        routes: [
          GoRoute(path: '/organizer', builder: (c, s) => const OrganizerDashboardScreen()),
          GoRoute(path: '/organizer/events', builder: (c, s) => const OrganizerEventsScreen()),
          GoRoute(path: '/organizer/events/new', builder: (c, s) => const EventFormScreen()),
          GoRoute(path: '/organizer/events/:id', builder: (c, s) => EventManageScreen(eventId: s.pathParameters['id']!)),
          GoRoute(path: '/organizer/events/:id/edit', builder: (c, s) => EventFormScreen(eventId: s.pathParameters['id'])),
          GoRoute(path: '/organizer/events/:id/live', builder: (c, s) => LiveEventScreen(eventId: s.pathParameters['id']!)),
          GoRoute(path: '/organizer/events/:id/analytics', builder: (c, s) => EventAnalyticsScreen(eventId: s.pathParameters['id']!)),
          GoRoute(path: '/organizer/analytics', builder: (c, s) => const ClubAnalyticsScreen()),
        ],
      ),

      // Campus operations --------------------------------------------------
      ShellRoute(
        builder: (c, s, child) => DashboardShell(title: 'Campus Ops', requiredRoles: const {Role.campusAdmin}, destinations: const [
          DashboardDestination('/admin', 'Dashboard', Icons.dashboard_outlined),
          DashboardDestination('/admin/pilot', 'Pilot scorecard', Icons.flag_outlined),
          DashboardDestination('/admin/review', 'Event review', Icons.rule_folder_outlined),
          DashboardDestination('/admin/organizers', 'Organizers & roles', Icons.groups_outlined),
          DashboardDestination('/admin/users', 'Users', Icons.people_outline),
          DashboardDestination('/admin/rewards', 'Rewards', Icons.card_giftcard_outlined),
          DashboardDestination('/admin/vendors', 'Vendors & settlement', Icons.storefront_outlined),
          DashboardDestination('/admin/fraud', 'QR & fraud review', Icons.security_outlined),
          DashboardDestination('/admin/notifications', 'Notifications', Icons.notifications_outlined),
          DashboardDestination('/admin/quests', 'Brand quests', Icons.workspace_premium_outlined),
          DashboardDestination('/admin/surveys', 'Surveys', Icons.poll_outlined),
          DashboardDestination('/admin/institutional', 'Institutional', Icons.school_outlined),
          DashboardDestination('/admin/config', 'Configuration', Icons.tune),
          DashboardDestination('/admin/audit', 'Audit log', Icons.history),
        ], child: child),
        routes: [
          GoRoute(path: '/admin', builder: (c, s) => const AdminDashboardScreen()),
          GoRoute(path: '/admin/pilot', builder: (c, s) => const PilotScorecardScreen()),
          GoRoute(path: '/admin/review', builder: (c, s) => const EventReviewScreen()),
          GoRoute(path: '/admin/organizers', builder: (c, s) => const OrganizersScreen()),
          GoRoute(path: '/admin/users', builder: (c, s) => const UsersScreen()),
          GoRoute(path: '/admin/rewards', builder: (c, s) => const AdminRewardsScreen()),
          GoRoute(path: '/admin/vendors', builder: (c, s) => const VendorsScreen()),
          GoRoute(path: '/admin/fraud', builder: (c, s) => const FraudReviewScreen()),
          GoRoute(path: '/admin/notifications', builder: (c, s) => const NotificationComposerScreen()),
          GoRoute(path: '/admin/quests', builder: (c, s) => const AdminQuestsScreen()),
          GoRoute(path: '/admin/surveys', builder: (c, s) => const AdminSurveysScreen()),
          GoRoute(path: '/admin/institutional', builder: (c, s) => const InstitutionalScreen()),
          GoRoute(path: '/admin/config', builder: (c, s) => const CampusConfigScreen()),
          GoRoute(path: '/admin/audit', builder: (c, s) => const AuditLogScreen()),
        ],
      ),

      // Brand ---------------------------------------------------------------
      ShellRoute(
        builder: (c, s, child) => DashboardShell(title: 'Brand', requiredRoles: const {Role.brand, Role.superAdmin}, destinations: const [
          DashboardDestination('/brand', 'Quests', Icons.workspace_premium_outlined),
          DashboardDestination('/brand/quests/new', 'New quest', Icons.add_circle_outline),
        ], child: child),
        routes: [
          GoRoute(path: '/brand', builder: (c, s) => const BrandDashboardScreen()),
          GoRoute(path: '/brand/quests/new', builder: (c, s) => const QuestFormScreen()),
          GoRoute(path: '/brand/quests/:id', builder: (c, s) => BrandQuestScreen(questId: s.pathParameters['id']!)),
          GoRoute(path: '/brand/quests/:id/edit', builder: (c, s) => QuestFormScreen(questId: s.pathParameters['id'])),
        ],
      ),

      // Vendor / Ambassador / Super admin --------------------------------
      ShellRoute(
        builder: (c, s, child) => DashboardShell(title: 'Partner', requiredRoles: const {Role.vendor, Role.campusAdmin}, destinations: const [
          DashboardDestination('/vendor', 'Redeem', Icons.qr_code_scanner),
          DashboardDestination('/vendor/settlement', 'Settlement', Icons.receipt_long_outlined),
        ], child: child),
        routes: [
          GoRoute(path: '/vendor', builder: (c, s) => const VendorRedeemScreen()),
          GoRoute(path: '/vendor/settlement', builder: (c, s) => const VendorSettlementScreen()),
        ],
      ),
      GoRoute(path: '/ambassador', parentNavigatorKey: _rootKey, builder: (c, s) => const AmbassadorScreen()),
      ShellRoute(
        builder: (c, s, child) => DashboardShell(title: 'Platform', requiredRoles: const {Role.superAdmin}, destinations: const [
          DashboardDestination('/super', 'Campuses', Icons.location_city_outlined),
          DashboardDestination('/super/brands', 'Brands', Icons.storefront_outlined),
          DashboardDestination('/super/entitlements', 'Entitlements', Icons.verified_outlined),
        ], child: child),
        routes: [
          GoRoute(path: '/super', builder: (c, s) => const SuperCampusesScreen()),
          GoRoute(path: '/super/brands', builder: (c, s) => const SuperBrandsScreen()),
          GoRoute(path: '/super/entitlements', builder: (c, s) => const SuperEntitlementsScreen()),
        ],
      ),
    ],
    errorBuilder: (c, s) => Scaffold(appBar: AppBar(), body: Center(child: Text("That page doesn't exist.", style: Theme.of(c).textTheme.titleLarge))),
  );
  final deepLinks = DeepLinkService(router);
  unawaited(deepLinks.init());
  ref.onDispose(() { deepLinks.dispose(); router.dispose(); notifier.dispose(); });
  return router;
});
