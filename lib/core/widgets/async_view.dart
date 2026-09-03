import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state_views.dart';

/// Renders an AsyncValue with loading/error/data states consistently.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.loading, this.skeleton = false});
  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;
  final bool skeleton;
  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        loading: () => loading ?? (skeleton ? const CbSkeletonList() : const CbLoading()),
        error: (e, _) => CbErrorView(error: e, onRetry: onRetry),
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
      );
}
