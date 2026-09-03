import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/state_views.dart';
import '../../events/data/event_repository.dart';

/// 1–5 stars, optional review, optional anonymity. Only verified attendees succeed (server-enforced).
class FeedbackScreen extends ConsumerStatefulWidget {
  const FeedbackScreen({super.key, required this.eventId});
  final String eventId;
  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  int _rating = 0; final _review = TextEditingController(); bool _anonymous = false, _busy = false;
  final Set<String> _tags = {};
  static const _quick = ['Well organised', 'Great speaker', 'Ran late', 'Venue too small', 'Would come again', 'Sound issues'];

  @override
  void initState() { super.initState(); ref.read(analyticsProvider).track('feedback_prompted', {'eventId': widget.eventId}); }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final text = [_review.text.trim(), if (_tags.isNotEmpty) _tags.join(' · ')].where((s) => s.isNotEmpty).join('\n');
      final r = await ref.read(eventActionsProvider).submitFeedback(widget.eventId, _rating, text.isEmpty ? null : text, anonymous: _anonymous);
      final coins = (r['coinsAwarded'] as num?)?.toInt() ?? 0;
      if (mounted) { showCbSnack(context, coins > 0 ? 'Thanks. +$coins BuzzCoins.' : 'Thanks for the feedback.'); context.pop(); }
    } catch (e) {
      if (mounted) showCbError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = ref.watch(eventProvider(widget.eventId)).value;
    final existing = ref.watch(myFeedbackProvider(widget.eventId)).value;
    final checkin = ref.watch(myCheckinProvider(widget.eventId)).value;
    final t = Theme.of(context).textTheme;
    if (existing != null) return Scaffold(appBar: AppBar(title: const Text('Feedback')), body: const CbEmpty(icon: Icons.check_circle_outline, title: 'Already reviewed', message: 'Thanks — your rating is in.'));
    if (checkin == null) return Scaffold(appBar: AppBar(title: const Text('Feedback')), body: const CbEmpty(icon: Icons.qr_code_2, title: 'Check in first', message: 'Only verified attendees can review an event.'));
    return Scaffold(
      appBar: AppBar(title: const Text('How was it?')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text(event?.title ?? '', style: t.headlineSmall),
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (var i = 1; i <= 5; i++) IconButton(iconSize: 44, tooltip: '$i star${i > 1 ? 's' : ''}', onPressed: () => setState(() => _rating = i), icon: Icon(i <= _rating ? Icons.star : Icons.star_border, color: i <= _rating ? CbColors.warning : CbColors.textTertiary))]),
        Center(child: Text(_rating == 0 ? 'Tap a star' : ['', 'Not great', 'Meh', 'Good', 'Great', 'Best event this semester'][_rating], style: t.bodyMedium)),
        const SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final q in _quick) FilterChip(label: Text(q), selected: _tags.contains(q), onSelected: (v) => setState(() => v ? _tags.add(q) : _tags.remove(q)))]),
        const SizedBox(height: 16),
        TextField(controller: _review, maxLines: 4, maxLength: 500, decoration: const InputDecoration(hintText: 'Anything the organizer should know? (optional)')),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Post anonymously'), subtitle: const Text('Your name stays off the review'), value: _anonymous, onChanged: (v) => setState(() => _anonymous = v)),
        const SizedBox(height: 12),
        FilledButton(onPressed: _rating == 0 || _busy ? null : _submit, child: Text(_busy ? 'Sending…' : 'Submit · +${ref.watch(economyProvider).feedbackReward} BuzzCoins')),
      ]),
    );
  }
}
