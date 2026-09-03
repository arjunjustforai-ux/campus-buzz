import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/auth/auth_providers.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/feature_flags.dart';
import '../../../core/errors/app_error.dart';
import '../../../core/network/functions_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/cb_widgets.dart';
import '../../../core/widgets/state_views.dart';

/// Scan → send token to `checkInWithQr` → success/failure sheet. The QR is just
/// a transport; validation is server-side.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final MobileScannerController _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates, formats: const [BarcodeFormat.qrCode]);
  bool _busy = false; String? _lastToken; final _manual = TextEditingController();

  @override
  void dispose() { _controller.dispose(); _manual.dispose(); super.dispose(); }

  Future<void> _submit(String token) async {
    if (_busy || token == _lastToken) return;
    _lastToken = token;
    setState(() => _busy = true);
    ref.read(analyticsProvider).track('qr_scan_started');
    try {
      final r = await ref.read(functionsProvider).call('checkInWithQr', {'token': token});
      if (!mounted) return;
      await _showResult(success: true, result: r);
    } catch (e) {
      if (!mounted) return;
      await _showResult(success: false, error: AppError.from(e));
    } finally {
      if (mounted) setState(() => _busy = false);
      Future.delayed(const Duration(seconds: 3), () => _lastToken = null);
    }
  }

  Future<void> _showResult({required bool success, Map<String, dynamic>? result, AppError? error}) async {
    final t = Theme.of(context).textTheme;
    final coins = (result?['coins'] as num?)?.toInt() ?? 0;
    final already = result?['alreadyCheckedIn'] == true;
    final streak = (result?['streak'] as num?)?.toInt() ?? 0;
    final title = success ? (already ? "You're already checked in." : "You're checked in.") : 'Check-in failed';
    await showModalBottomSheet(
      context: context,
      isDismissible: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(success ? Icons.verified : Icons.error_outline, size: 56, color: success ? CbColors.lime : CbColors.danger),
            const SizedBox(height: 12),
            Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            if (success) Text(result?['eventTitle'] as String? ?? '', style: t.bodyLarge, textAlign: TextAlign.center),
            if (success && coins > 0) Padding(padding: const EdgeInsets.only(top: 12), child: Center(child: CbCoinBadge(amount: coins, large: true))),
            if (success && result?['multiplierApplied'] == true) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Streak bonus applied — ${streak} weeks in a row.', style: t.bodyMedium?.copyWith(color: CbColors.limeText), textAlign: TextAlign.center)),
            if (success && result?['multiplierApplied'] != true && streak > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Week $streak of your streak.', style: t.bodyMedium, textAlign: TextAlign.center)),
            if (!success) Text(error?.message ?? '', style: t.bodyLarge, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (success) FilledButton(onPressed: () { Navigator.pop(ctx); context.go('/home'); }, child: const Text('Done')),
            if (!success) FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Try again')),
            if (!success) TextButton(onPressed: () { Navigator.pop(ctx); context.push('/support'); }, child: const Text('Tell the organizer / get help')),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(flagProvider(FeatureFlag.qrCheckinEnabled));
    final t = Theme.of(context).textTheme;
    if (!enabled) return Scaffold(appBar: AppBar(title: const Text('Scan')), body: const CbEmpty(icon: Icons.qr_code_2, title: 'QR check-in is coming soon', message: 'Your campus is still setting up verified attendance.'));
    return Scaffold(
      appBar: AppBar(title: const Text('Scan to check in'), actions: [
        IconButton(tooltip: 'Toggle torch', onPressed: () => _controller.toggleTorch(), icon: const Icon(Icons.flashlight_on_outlined)),
        IconButton(tooltip: 'Switch camera', onPressed: () => _controller.switchCamera(), icon: const Icon(Icons.cameraswitch_outlined)),
      ]),
      body: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            MobileScanner(
              controller: _controller,
              onDetect: (capture) { final raw = capture.barcodes.firstOrNull?.rawValue; if (raw != null && raw.contains('.')) _submit(raw); },
              errorBuilder: (context, error) => _PermissionView(error: error, onRetry: () => _controller.start()),
            ),
            IgnorePointer(child: Center(child: Container(width: 240, height: 240, decoration: BoxDecoration(border: Border.all(color: _busy ? CbColors.orange : CbColors.lime, width: 3), borderRadius: BorderRadius.circular(24))))),
            if (_busy) const Center(child: CircularProgressIndicator()),
            Positioned(left: 0, right: 0, bottom: 16, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: CbColors.dark.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(999)), child: Text(_busy ? 'Verifying…' : "Point at the organizer's rotating QR", style: t.labelLarge)))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Scan the organizer\'s QR at the venue. It rotates every 30 seconds and only counts inside the check-in window.', style: t.bodySmall, textAlign: TextAlign.center),
            if (kIsWeb || AppConfig.useEmulators) ...[
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _manual, decoration: const InputDecoration(hintText: 'Paste check-in token (dev/web)', isDense: true))),
                const SizedBox(width: 8),
                FilledButton(onPressed: _busy ? null : () => _submit(_manual.text.trim()), child: const Text('Check in')),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _PermissionView extends StatelessWidget {
  const _PermissionView({required this.error, required this.onRetry});
  final MobileScannerException error; final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return CbEmpty(icon: denied ? Icons.no_photography_outlined : Icons.videocam_off_outlined, title: denied ? 'Camera access needed' : 'Camera unavailable', message: denied ? 'Allow camera access in Settings to scan the check-in QR. Organizers can also check you in manually.' : 'Try again, or ask the organizer for a manual check-in.', actionLabel: 'Retry', action: onRetry);
  }
}
