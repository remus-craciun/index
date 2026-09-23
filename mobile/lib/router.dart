import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'core/session/session_controller.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/auth/presentation/server_setup_screen.dart';
import 'features/calendar/presentation/calendar_screen.dart';
import 'features/history/presentation/history_screen.dart';
import 'features/plans/presentation/ai_plan_screen.dart';
import 'features/plans/presentation/plan_detail_screen.dart';
import 'features/plans/presentation/plans_screen.dart';
import 'features/routines/presentation/routines_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/shell/home_shell.dart';
import 'features/tasks/presentation/inbox_screen.dart';
import 'features/today/presentation/today_screen.dart';

part 'router.g.dart';

/// Where the session state says the user must be, or null if anywhere in
/// the app is fine.
String? sessionRedirect(AsyncValue<Session> session, String location) {
  const gates = {'/splash', '/setup', '/auth'};
  String? go(String target) => location == target ? null : target;

  if (!session.hasValue) return session.isLoading ? go('/splash') : go('/setup');
  final s = session.requireValue;
  if (s.serverUrl == null) return go('/setup');
  if (!s.authenticated) return go('/auth');
  if (gates.contains(location)) return '/today';
  return null;
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final session = ValueNotifier<AsyncValue<Session>>(ref.read(sessionControllerProvider));
  ref.listen(sessionControllerProvider, (_, next) => session.value = next);
  ref.onDispose(session.dispose);

  return GoRouter(
    initialLocation: '/today',
    refreshListenable: session,
    redirect: (context, state) => sessionRedirect(session.value, state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/setup', builder: (_, _) => const ServerSetupScreen()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/routines', builder: (_, _) => const RoutinesScreen()),
      GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
      GoRoute(path: '/plans/new', builder: (_, _) => const AiPlanScreen()),
      GoRoute(
        path: '/plans/:id',
        builder: (_, state) => PlanDetailScreen(planId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/today', builder: (_, _) => const TodayScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/inbox', builder: (_, _) => const InboxScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/calendar', builder: (_, _) => const CalendarScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/plans', builder: (_, _) => const PlansScreen())]),
        ],
      ),
    ],
  );
}
