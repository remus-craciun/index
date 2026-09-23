import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/sync/sync_controller.dart';
import 'core/ui/theme.dart';
import 'core/ui/widgets.dart';
import 'features/repositories.dart';
import 'router.dart';

class IndexApp extends ConsumerStatefulWidget {
  const IndexApp({super.key});

  @override
  ConsumerState<IndexApp> createState() => _IndexAppState();
}

class _IndexAppState extends ConsumerState<IndexApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(currentDayProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep background services running for the app's lifetime.
    ref.listen(syncControllerProvider, (_, _) {});
    ref.listen(routineGeneratorProvider, (_, _) {});
    ref.listen(reminderSchedulerProvider, (_, _) {});
    return MaterialApp.router(
      title: 'Index',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootMessengerKey,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
