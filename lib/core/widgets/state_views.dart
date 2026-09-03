import 'package:flutter/material.dart';

import '../errors/app_error.dart';
import '../theme/app_colors.dart';

/// Loading / empty / error states used on every screen. No blank screens.
class CbLoading extends StatelessWidget {
  const CbLoading({super.key, this.message});
  final String? message;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          if (message != null) ...[const SizedBox(height: 12), Text(message!, style: Theme.of(context).textTheme.bodyMedium)],
        ]),
      );
}

class CbEmpty extends StatelessWidget {
  const CbEmpty({super.key, required this.title, this.message, this.icon = Icons.auto_awesome_outlined, this.action, this.actionLabel});
  final String title;
  final String? message, actionLabel;
  final IconData icon;
  final VoidCallback? action;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 64, height: 64, decoration: const BoxDecoration(gradient: CbColors.gradientSoft, shape: BoxShape.circle), child: Icon(icon, color: CbColors.limeText, size: 30)),
          const SizedBox(height: 16),
          Text(title, style: t.titleLarge, textAlign: TextAlign.center),
          if (message != null) ...[const SizedBox(height: 8), Text(message!, style: t.bodyMedium, textAlign: TextAlign.center)],
          if (action != null) ...[const SizedBox(height: 20), OutlinedButton(onPressed: action, child: Text(actionLabel ?? 'Try again'))],
        ]),
      ),
    );
  }
}

class CbErrorView extends StatelessWidget {
  const CbErrorView({super.key, required this.error, this.onRetry, this.compact = false});
  final Object error;
  final VoidCallback? onRetry;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final e = AppError.from(error);
    final t = Theme.of(context).textTheme;
    final permission = e.code == 'permission_denied' || e.code == 'permission-denied';
    if (compact) {
      return Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Icon(Icons.error_outline, color: CbColors.danger, size: 18), const SizedBox(width: 8), Expanded(child: Text(e.message, style: t.bodyMedium)), if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry'))]));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(permission ? Icons.lock_outline : Icons.wifi_off_rounded, color: permission ? CbColors.warning : CbColors.danger, size: 40),
          const SizedBox(height: 16),
          Text(permission ? 'No access' : 'Something broke', style: t.titleLarge),
          const SizedBox(height: 8),
          Text(e.message, style: t.bodyMedium, textAlign: TextAlign.center),
          if (onRetry != null && !permission) ...[const SizedBox(height: 20), FilledButton(onPressed: onRetry, child: const Text('Try again'))],
        ]),
      ),
    );
  }
}

/// Skeleton placeholder for list loading.
class CbSkeleton extends StatefulWidget {
  const CbSkeleton({super.key, this.height = 120, this.width = double.infinity, this.radius = 16});
  final double height, width, radius;
  @override
  State<CbSkeleton> createState() => _CbSkeletonState();
}

class _CbSkeletonState extends State<CbSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Container(height: widget.height, width: widget.width, decoration: BoxDecoration(color: Color.lerp(CbColors.surface2, CbColors.surface3, _c.value), borderRadius: BorderRadius.circular(widget.radius))),
      );
}

class CbSkeletonList extends StatelessWidget {
  const CbSkeletonList({super.key, this.count = 4, this.height = 140});
  final int count; final double height;
  @override
  Widget build(BuildContext context) => ListView.separated(padding: const EdgeInsets.all(16), itemCount: count, separatorBuilder: (_, __) => const SizedBox(height: 12), itemBuilder: (_, __) => CbSkeleton(height: height));
}

/// Async value → widget with consistent states.
extension AsyncViews<T> on AsyncSnapshotLike<T> {}

typedef AsyncSnapshotLike<T> = T;

void showCbSnack(BuildContext context, String message, {bool error = false, IconData? icon}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [Icon(icon ?? (error ? Icons.error_outline : Icons.check_circle_outline), color: error ? CbColors.danger : CbColors.limeText, size: 20), const SizedBox(width: 10), Expanded(child: Text(message))]),
    ));
}

void showCbError(BuildContext context, Object e) => showCbSnack(context, AppError.from(e).message, error: true);
