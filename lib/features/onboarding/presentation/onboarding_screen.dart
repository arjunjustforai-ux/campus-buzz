import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/models/models.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';
import 'auth_screens.dart';

/// Name → Tribes (≥3, one primary) → notification prefs → consent → completeOnboarding.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final _name = TextEditingController();
  final _referral = TextEditingController();
  final Set<String> _tribes = {};
  String? _primary;
  bool _reminders = true, _engagement = true, _postEvent = true, _consent = false, _busy = false;
  String? _error; String? _campusId; String? _campusName; Campus? _campus;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track('onboarding_started');
    _referral.text = ref.read(pendingReferralProvider) ?? '';
    _resolve();
  }

  Future<void> _resolve() async {
    final email = ref.read(authStateProvider).value?.email;
    if (email == null) return;
    try {
      final r = await ref.read(functionsProvider).call('resolveCampusForEmail', {'email': email});
      if (r['supported'] == true) {
        final snap = await ref.read(firestoreProvider).collection(Col.campuses).doc(r['campusId'] as String).get();
        setState(() { _campusId = r['campusId'] as String; _campusName = r['campusName'] as String?; _campus = snap.exists ? Campus.fromDoc(snap) : null; });
      } else {
        setState(() => _error = "Your college email isn't on a supported campus yet.");
      }
    } catch (e) {
      setState(() => _error = AppError.from(e).message);
    }
  }

  Future<void> _finish() async {
    setState(() { _busy = true; _error = null; });
    try {
      final r = await ref.read(functionsProvider).call('completeOnboarding', {
        'displayName': _name.text.trim(), 'tribeIds': _tribes.toList(), 'primaryTribeId': _primary, 'consentAccepted': _consent,
        'referralCode': _referral.text.trim().isEmpty ? null : _referral.text.trim(),
        'notificationPrefs': {'reminders': _reminders, 'engagement': _engagement, 'postEvent': _postEvent},
      });
      ref.read(analyticsProvider).track('tribe_selected', {'tribeIds': _tribes.toList()});
      if (r['referral'] == 'invalid' && mounted) showCbSnack(context, "Referral code didn't match anyone — you're in anyway.", error: true);
      // Router redirects to /home once the profile stream reports onboardingCompleted.
    } catch (e) {
      setState(() => _error = AppError.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tribes = _campusId == null ? const AsyncValue<List<Tribe>>.loading() : ref.watch(_campusTribesProvider(_campusId!));
    final steps = [
      _StepName(name: _name, campusName: _campusName),
      tribes.when(
        loading: () => const CbLoading(message: 'Loading your campus Tribes…'),
        error: (e, _) => CbErrorView(error: e, onRetry: () => ref.invalidate(_campusTribesProvider(_campusId!))),
        data: (list) => _StepTribes(tribes: list, selected: _tribes, primary: _primary, onToggle: (id) => setState(() { if (!_tribes.remove(id)) _tribes.add(id); if (_primary != null && !_tribes.contains(_primary)) _primary = null; _primary ??= _tribes.isEmpty ? null : _tribes.first; }), onPrimary: (id) => setState(() => _primary = id)),
      ),
      _StepPrefs(reminders: _reminders, engagement: _engagement, postEvent: _postEvent, consent: _consent, referral: _referral, campus: _campus, onChanged: (r, e, p, c) => setState(() { _reminders = r; _engagement = e; _postEvent = p; _consent = c; })),
    ];
    final canNext = switch (_step) { 0 => _name.text.trim().length >= 2 && _campusId != null, 1 => _tribes.length >= 3 && _primary != null, _ => _consent };
    return Scaffold(
      appBar: AppBar(title: Text(['Your name', 'Your Tribes', 'Almost there'][_step]), leading: _step > 0 ? BackButton(onPressed: () => setState(() => _step--)) : null, actions: [TextButton(onPressed: () => ref.read(firebaseAuthProvider).signOut(), child: const Text('Sign out'))]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(children: [
              LinearProgressIndicator(value: (_step + 1) / 3, minHeight: 3),
              Expanded(child: Padding(padding: const EdgeInsets.all(20), child: steps[_step])),
              if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(_error!, style: t.bodyMedium?.copyWith(color: CbColors.danger))),
              Padding(
                padding: const EdgeInsets.all(20),
                child: FilledButton(
                  onPressed: !canNext || _busy ? null : () => _step < 2 ? setState(() => _step++) : _finish(),
                  child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_step < 2 ? 'Continue' : "Let's go"),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

final _campusTribesProvider = StreamProvider.family<List<Tribe>, String>((ref, campusId) => FirebaseFirestore.instance.collection(Col.tribes).where('campusId', isEqualTo: campusId).snapshots().map((s) => (s.docs.map(Tribe.fromDoc).where((t) => t.active).toList())..sort((a, b) => a.order.compareTo(b.order))));

class _StepName extends StatelessWidget {
  const _StepName({required this.name, required this.campusName});
  final TextEditingController name; final String? campusName;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(children: [
      Text('What should we call you?', style: t.headlineMedium),
      const SizedBox(height: 8),
      Text(campusName != null ? "You're joining $campusName." : 'Resolving your campus…', style: t.bodyLarge?.copyWith(color: CbColors.textSecondary)),
      const SizedBox(height: 24),
      TextField(controller: name, textCapitalization: TextCapitalization.words, autofocus: true, onChanged: (_) => (context as Element).markNeedsBuild(), decoration: const InputDecoration(labelText: 'Full name')),
    ]);
  }
}

class _StepTribes extends StatelessWidget {
  const _StepTribes({required this.tribes, required this.selected, required this.primary, required this.onToggle, required this.onPrimary});
  final List<Tribe> tribes; final Set<String> selected; final String? primary; final ValueChanged<String> onToggle, onPrimary;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(children: [
      Text('Pick at least 3 Tribes.', style: t.headlineMedium),
      const SizedBox(height: 8),
      Text('This is how CampusBuzz knows what "happening for people like me" means. Star one as your main Tribe.', style: t.bodyLarge?.copyWith(color: CbColors.textSecondary)),
      const SizedBox(height: 20),
      if (tribes.isEmpty) const CbEmpty(title: 'No Tribes yet', message: 'Campus operations is still setting things up.'),
      for (final tr in tribes)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CbCard(
            onTap: () => onToggle(tr.id),
            borderColor: selected.contains(tr.id) ? CbColors.lime : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Text(tr.emoji.isEmpty ? '•' : tr.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr.name, style: t.titleMedium), if (tr.description.isNotEmpty) Text(tr.description, style: t.bodySmall)])),
              if (selected.contains(tr.id)) IconButton(tooltip: 'Make main Tribe', onPressed: () => onPrimary(tr.id), icon: Icon(primary == tr.id ? Icons.star : Icons.star_border, color: primary == tr.id ? CbColors.lime : CbColors.textTertiary)),
              Icon(selected.contains(tr.id) ? Icons.check_circle : Icons.circle_outlined, color: selected.contains(tr.id) ? CbColors.lime : CbColors.textTertiary),
            ]),
          ),
        ),
      const SizedBox(height: 8),
      Text('${selected.length}/3 selected', style: t.labelMedium),
    ]);
  }
}

class _StepPrefs extends StatelessWidget {
  const _StepPrefs({required this.reminders, required this.engagement, required this.postEvent, required this.consent, required this.referral, required this.campus, required this.onChanged});
  final bool reminders, engagement, postEvent, consent; final TextEditingController referral; final Campus? campus;
  final void Function(bool reminders, bool engagement, bool postEvent, bool consent) onChanged;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final privacy = campus?.privacyPolicyUrl ?? 'https://campusbuzz.app/privacy';
    final terms = campus?.termsUrl ?? 'https://campusbuzz.app/terms';
    return ListView(children: [
      Text('Notifications, your way.', style: t.headlineMedium),
      const SizedBox(height: 8),
      Text('At most 2 nudges a day. Cancellations and security alerts always get through.', style: t.bodyLarge?.copyWith(color: CbColors.textSecondary)),
      const SizedBox(height: 12),
      SwitchListTile(title: const Text('Event reminders'), subtitle: const Text('24h and 1h before events you RSVP to'), value: reminders, onChanged: (v) => onChanged(v, engagement, postEvent, consent)),
      SwitchListTile(title: const Text('Tribe picks & rewards'), subtitle: const Text('Events for your Tribes, new rewards, streak reminders'), value: engagement, onChanged: (v) => onChanged(reminders, v, postEvent, consent)),
      SwitchListTile(title: const Text('Post-event feedback'), subtitle: const Text('A quick rating request after you check in'), value: postEvent, onChanged: (v) => onChanged(reminders, engagement, v, consent)),
      const SizedBox(height: 12),
      TextField(controller: referral, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Referral code (optional)')),
      const SizedBox(height: 16),
      CheckboxListTile(
        value: consent,
        onChanged: (v) => onChanged(reminders, engagement, postEvent, v == true),
        controlAffinity: ListTileControlAffinity.leading,
        title: Wrap(children: [
          const Text('I agree to the '),
          InkWell(onTap: () => launchUrl(Uri.parse(terms), mode: LaunchMode.externalApplication), child: const Text('Terms of Service', style: TextStyle(color: CbColors.limeText, decoration: TextDecoration.underline))),
          const Text(' and '),
          InkWell(onTap: () => launchUrl(Uri.parse(privacy), mode: LaunchMode.externalApplication), child: const Text('Privacy Policy', style: TextStyle(color: CbColors.limeText, decoration: TextDecoration.underline))),
          const Text('.'),
        ]),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('We collect your name, college email, Tribes and event activity — nothing else. Brands only ever see aggregate numbers.', style: t.bodySmall)),
    ]);
  }
}
