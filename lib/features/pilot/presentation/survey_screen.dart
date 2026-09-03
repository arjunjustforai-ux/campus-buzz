import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/constants/collections.dart';
import '../../../core/models/models.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';

final surveyProvider = StreamProvider.family<Survey?, String>((ref, id) => ref.watch(firestoreProvider).collection(Col.surveys).doc(id).snapshots().map((s) => s.exists ? Survey.fromDoc(s) : null));

/// Pilot pulse survey: love / annoys / would miss / helped attend / NPS 0–10.
class SurveyScreen extends ConsumerStatefulWidget {
  const SurveyScreen({super.key, required this.surveyId});
  final String surveyId;
  @override
  ConsumerState<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends ConsumerState<SurveyScreen> {
  final _love = TextEditingController(), _annoys = TextEditingController();
  String? _wouldMiss; bool _helped = false; int? _nps; bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await ref.read(functionsProvider).call('submitSurveyResponse', {'surveyId': widget.surveyId, 'answers': {'love': _love.text.trim(), 'annoys': _annoys.text.trim(), 'wouldMiss': _wouldMiss, 'helpedAttend': _helped, 'nps': _nps}});
      if (mounted) { showCbSnack(context, 'Thanks — this shapes the pilot.'); context.pop(); }
    } catch (e) { if (mounted) showCbError(context, e); } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final survey = ref.watch(surveyProvider(widget.surveyId)).value;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(survey?.title ?? 'Survey')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('60 seconds. Honest answers help most.', style: t.bodyMedium),
        const SizedBox(height: 16),
        TextField(controller: _love, maxLength: 500, decoration: const InputDecoration(labelText: 'What do you love?')),
        TextField(controller: _annoys, maxLength: 500, decoration: const InputDecoration(labelText: 'What annoys you?')),
        const SizedBox(height: 12),
        Text('Would you miss CampusBuzz if it disappeared?', style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [for (final o in const [('strongly_yes', 'Definitely'), ('yes', 'Yes'), ('unsure', 'Not sure'), ('no', 'No')]) CbChip(label: o.$2, selected: _wouldMiss == o.$1, onTap: () => setState(() => _wouldMiss = o.$1))]),
        const SizedBox(height: 12),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('CampusBuzz helped me attend an event I would have missed'), value: _helped, onChanged: (v) => setState(() => _helped = v)),
        const SizedBox(height: 12),
        Text('How likely are you to recommend CampusBuzz to a friend? (0–10)', style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [for (var i = 0; i <= 10; i++) CbChip(label: '$i', selected: _nps == i, color: _nps == i ? (i >= 9 ? CbColors.lime : i >= 7 ? CbColors.warning : CbColors.orange) : null, onTap: () => setState(() => _nps = i))]),
        const SizedBox(height: 24),
        FilledButton(onPressed: _wouldMiss == null || _nps == null || _busy ? null : _submit, child: const Text('Submit')),
      ]),
    );
  }
}
