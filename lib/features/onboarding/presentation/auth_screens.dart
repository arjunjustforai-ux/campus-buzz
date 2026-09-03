import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: _Wordmark(size: 40)));
}

class _Wordmark extends StatelessWidget {
  const _Wordmark({this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: size, height: size, decoration: BoxDecoration(gradient: CbColors.gradient, borderRadius: BorderRadius.circular(size * 0.3)), child: Icon(Icons.bolt, color: CbColors.dark, size: size * 0.65)),
        const SizedBox(width: 10),
        Text('CampusBuzz', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: size * 0.85)),
      ]);
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.children, this.subtitle, this.showBack = true});
  final String title; final String? subtitle; final List<Widget> children; final bool showBack;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: showBack ? AppBar(leading: BackButton(onPressed: () => context.canPop() ? context.pop() : context.go('/welcome'))) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const _Wordmark(),
                const SizedBox(height: 28),
                Text(title, style: t.displaySmall),
                if (subtitle != null) ...[const SizedBox(height: 8), Text(subtitle!, style: t.bodyLarge?.copyWith(color: CbColors.textSecondary))],
                const SizedBox(height: 24),
                ...children,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Stack(children: [
        Positioned(right: -80, top: -60, child: Container(width: 260, height: 260, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [CbColors.orange.withValues(alpha: 0.35), CbColors.lime.withValues(alpha: 0.1)])))),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisAlignment: MainAxisAlignment.center, children: [
                  const _Wordmark(size: 36),
                  const Spacer(),
                  Text('Show up.\nEarn rewards.\nFind your tribe.', style: t.displayMedium?.copyWith(height: 1.05)),
                  const SizedBox(height: 16),
                  Text('The operating system for campus culture. Every event on your campus, verified attendance, BuzzCoins you can actually spend.', style: t.bodyLarge?.copyWith(color: CbColors.textSecondary)),
                  const Spacer(),
                  FilledButton(onPressed: () => context.push('/register'), child: const Text('Join with college email')),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: () => context.push('/sign-in'), child: const Text('I already have an account')),
                  const SizedBox(height: 12),
                  Text("Don't miss what's happening.", textAlign: TextAlign.center, style: t.labelMedium?.copyWith(color: CbColors.limeText)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});
  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _busy = false; String? _error;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      ref.read(analyticsProvider).track('app_open', {'source': 'sign_in'});
    } catch (e) {
      setState(() => _error = AppError.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(
        title: 'Welcome back.',
        subtitle: 'Sign in with your college email.',
        children: [
          TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'College email')),
          const SizedBox(height: 12),
          TextField(controller: _password, obscureText: true, autofillHints: const [AutofillHints.password], onSubmitted: (_) => _submit(), decoration: const InputDecoration(labelText: 'Password')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: CbColors.danger))),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign in')),
          TextButton(onPressed: () => context.push('/forgot-password'), child: const Text('Forgot password?')),
          if (AppConfig.useEmulators) const _EmulatorAccounts(),
        ],
      );
}

class _EmulatorAccounts extends ConsumerWidget {
  const _EmulatorAccounts();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const accounts = ['student', 'organizer', 'ambassador', 'admin', 'brand', 'vendor', 'superadmin'];
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('EMULATOR DEMO ACCOUNTS', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in accounts)
            ActionChip(label: Text(a), onPressed: () async {
              try {
                await ref.read(firebaseAuthProvider).signInWithEmailAndPassword(email: '$a@demo.campusbuzz.test', password: 'CampusBuzz!123');
              } catch (e) {
                if (context.mounted) showCbError(context, e);
              }
            }),
        ]),
      ]),
    );
  }
}

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.referralCode});
  final String? referralCode;
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _busy = false, _checking = false; String? _error, _campusName; bool? _supported;

  Future<void> _checkCampus() async {
    final email = _email.text.trim();
    if (!email.contains('@')) return;
    setState(() { _checking = true; _supported = null; });
    try {
      final r = await ref.read(functionsProvider).call('resolveCampusForEmail', {'email': email});
      setState(() { _supported = r['supported'] == true; _campusName = r['campusName'] as String?; });
    } catch (e) {
      setState(() => _error = AppError.from(e).message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _submit() async {
    if (_supported != true) { await _checkCampus(); if (_supported != true) return; }
    if (_password.text.length < 8 || !RegExp(r'\d').hasMatch(_password.text)) { setState(() => _error = 'Use at least 8 characters with a number.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      ref.read(analyticsProvider).track('registration_started');
      final cred = await ref.read(firebaseAuthProvider).createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
      await cred.user?.sendEmailVerification();
      if (widget.referralCode != null) ref.read(pendingReferralProvider.notifier).set(widget.referralCode);
    } catch (e) {
      setState(() => _error = AppError.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AuthScaffold(
      title: 'Join your campus.',
      subtitle: 'Use your college email so we can put you on the right campus.',
      children: [
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, onChanged: (_) => setState(() => _supported = null), onEditingComplete: _checkCampus, decoration: InputDecoration(labelText: 'College email', suffixIcon: _checking ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : _supported == true ? const Icon(Icons.check_circle, color: CbColors.success) : _supported == false ? const Icon(Icons.error_outline, color: CbColors.danger) : null)),
        if (_supported == true) Padding(padding: const EdgeInsets.only(top: 8), child: Text('$_campusName · looks right.', style: t.bodyMedium?.copyWith(color: CbColors.limeText))),
        if (_supported == false) Padding(padding: const EdgeInsets.only(top: 8), child: Text("That email isn't on a supported campus yet. Ask your campus ambassador, or use your official college address.", style: t.bodyMedium?.copyWith(color: CbColors.warning))),
        const SizedBox(height: 12),
        TextField(controller: _password, obscureText: true, onSubmitted: (_) => _submit(), decoration: const InputDecoration(labelText: 'Password (8+ characters, one number)')),
        if (widget.referralCode != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Referral code ${widget.referralCode} will be applied after onboarding.', style: t.bodySmall)),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: CbColors.danger))),
        const SizedBox(height: 20),
        FilledButton(onPressed: _busy ? null : _submit, child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create account')),
        const SizedBox(height: 8),
        Text("You'll verify your email next. We only ask for name, college email and your interests — nothing else.", style: t.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}

/// Referral code captured from a deep link before the account exists.
class PendingReferral extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? code) => state = code;
}

final pendingReferralProvider = NotifierProvider<PendingReferral, String?>(PendingReferral.new);

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController(); bool _sent = false; String? _error;
  @override
  Widget build(BuildContext context) => AuthScaffold(title: 'Reset password', subtitle: "We'll email you a reset link.", children: [
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'College email')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: CbColors.danger))),
        const SizedBox(height: 20),
        FilledButton(onPressed: _sent ? null : () async { try { await ref.read(firebaseAuthProvider).sendPasswordResetEmail(email: _email.text.trim()); setState(() => _sent = true); } catch (e) { setState(() => _error = AppError.from(e).message); } }, child: Text(_sent ? 'Link sent — check your inbox' : 'Send reset link')),
      ]);
}

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _resent = false; bool _checking = false;
  Future<void> _check() async {
    setState(() => _checking = true);
    final user = ref.read(firebaseAuthProvider).currentUser;
    await user?.reload();
    // userChanges() fires after reload; router redirects automatically.
    if (mounted) setState(() => _checking = false);
    if (mounted && user != null && !(ref.read(firebaseAuthProvider).currentUser?.emailVerified ?? false)) showCbSnack(context, 'Not verified yet. Check your inbox (and spam).', error: true);
  }
  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authStateProvider).value?.email ?? '';
    return AuthScaffold(
      title: 'Check your inbox.',
      subtitle: 'We sent a verification link to $email. Tap it, then come back here.',
      showBack: false,
      children: [
        FilledButton(onPressed: _checking ? null : _check, child: Text(_checking ? 'Checking…' : "I've verified my email")),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _resent ? null : () async { await ref.read(firebaseAuthProvider).currentUser?.sendEmailVerification(); setState(() => _resent = true); }, child: Text(_resent ? 'Sent again' : 'Resend link')),
        if (AppConfig.allowEmulatorAuthShortcuts) Padding(padding: const EdgeInsets.only(top: 16), child: Text('Emulator: open http://${AppConfig.emulatorHost}:4000/auth and verify the email, or use a seeded demo account.', style: Theme.of(context).textTheme.bodySmall)),
        TextButton(onPressed: () => ref.read(firebaseAuthProvider).signOut(), child: const Text('Use a different email')),
      ],
    );
  }
}

class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = ref.watch(userProfileProvider).value?.suspensionReason;
    return AuthScaffold(
      title: 'Account paused.',
      subtitle: 'Campus operations paused this account${reason != null ? ': $reason' : '.'} You can still contact support to sort it out.',
      showBack: false,
      children: [
        FilledButton(onPressed: () => context.push('/support'), child: const Text('Contact campus support')),
        TextButton(onPressed: () => ref.read(firebaseAuthProvider).signOut(), child: const Text('Sign out')),
      ],
    );
  }
}

/// Re-exported so the router can reference it without an extra import.
User? currentFirebaseUser(WidgetRef ref) => ref.read(firebaseAuthProvider).currentUser;
