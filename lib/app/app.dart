import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/navigation/router.dart';
import '../core/theme/app_theme.dart';
import '../features/notifications/application/push_service.dart';

class CampusBuzzApp extends ConsumerStatefulWidget {
  const CampusBuzzApp({super.key});

  @override
  ConsumerState<CampusBuzzApp> createState() => _CampusBuzzAppState();
}

class _CampusBuzzAppState extends ConsumerState<CampusBuzzApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(pushServiceProvider).init());
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'CampusBuzz',
      debugShowCheckedModeBanner: false,
      theme: CbTheme.dark(),
      darkTheme: CbTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        // Respect text scaling but keep layouts sane on dashboards.
        data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.of(context).textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.4)),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
