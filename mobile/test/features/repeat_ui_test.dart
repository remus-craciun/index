import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/app.dart';
import 'package:index_app/core/db/app_database.dart';
import 'package:index_app/core/network/api.dart';
import 'package:index_app/core/network/token_store.dart';
import 'package:index_app/core/providers.dart';
import 'package:index_app/core/ui/widgets.dart';
import 'package:index_app/features/repositories.dart';
import 'package:index_app/features/routines/data/routines_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support.dart';
import 'app_flow_test.dart' show FakeAdapter;

/// Pumps the app already connected and signed in, landing on Today.
Future<AppDatabase> pumpSignedIn(WidgetTester tester, {List overrides = const []}) async {
  SharedPreferences.setMockInitialValues({'server_url': 'http://fake', 'data_server_url': 'http://fake'});
  final prefs = await SharedPreferences.getInstance();
  final db = memoryDb();
  final tokens = MemoryTokenStore()..write(const AuthTokens(accessToken: 'a', refreshToken: 'r'));
  final dio = Dio(BaseOptions(baseUrl: 'http://fake/api/v1'))..httpClientAdapter = FakeAdapter(FakeSyncServer());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appDatabaseProvider.overrideWithValue(db),
      tokenStoreProvider.overrideWithValue(tokens),
      apiProvider.overrideWithValue(Api.withDio(dio)),
      ...overrides,
    ],
    child: const IndexApp(),
  ));
  await tester.pumpAndSettle();
  return db;
}

Future<void> unmount(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  await tester.runAsync(db.close);
}

/// Simulates a local write failing, e.g. the schema mismatch seen after a
/// hot reload across a database upgrade.
class FailingRoutinesRepository extends RoutinesRepository {
  FailingRoutinesRepository(super.db) : super(onChanged: _noop);

  static void _noop() {}

  @override
  Future<String> createRoutine({
    required String title,
    String notes = '',
    String frequency = 'weekly',
    int repeatInterval = 1,
    required int weekdays,
    int? monthDay,
    String? startTime,
    String? endTime,
    int? estimatedMinutes,
    int? reminderMinutes,
    String? startDate,
    String? endDate,
  }) =>
      throw Exception('SqliteException(1): table recurrences has no column named month_day');
}

void main() {
  test('schema errors get an actionable message', () {
    expect(errorText(Exception('SqliteException(1): table recurrences has no column named month_day')),
        'The local database needs an update. Fully close and reopen the app.');
  });

  testWidgets('a failing save shows an error and keeps the editor open', (tester) async {
    late AppDatabase db;
    db = await pumpSignedIn(tester, overrides: [
      routinesRepositoryProvider.overrideWith((ref) => FailingRoutinesRepository(ref.watch(appDatabaseProvider))),
    ]);
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repeating tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New routine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Pay rent');
    await tester.tap(find.text('Monthly'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('The local database needs an update. Fully close and reopen the app.'), findsOneWidget);
    expect(find.text('New routine'), findsOneWidget, reason: 'editor stays open so nothing typed is lost');
    await unmount(tester, db);
  });

  testWidgets('a task can be made daily from its editor', (tester) async {
    final db = await pumpSignedIn(tester);
    expect(find.text('Nothing scheduled today'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Meditate');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Meditate'));
    await tester.pumpAndSettle();

    // Repeat options are visible on a one-off task.
    expect(find.text('Repeat'), findsOneWidget);
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Saving turns this into a routine'), findsOneWidget);
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('now repeats: every day'), findsOneWidget);

    // Today shows the routine's occurrence (with the repeat badge) instead of the one-off task.
    expect(find.text('Meditate'), findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsOneWidget);
    final tasks = await tester.runAsync(() => db.select(db.tasks).get());
    expect(tasks!.where((t) => t.deletedAt == null && t.recurrenceId == null), isEmpty);
    final routines = await tester.runAsync(() => db.select(db.recurrences).get());
    expect(routines!.single.frequency, 'daily');

    // Its editor now says it repeats and hides the Repeat chips.
    await tester.tap(find.text('Meditate'));
    await tester.pumpAndSettle();
    expect(find.text('Every day'), findsOneWidget);
    expect(find.text('Weekdays'), findsNothing);
    await tester.tapAt(const Offset(10, 10)); // dismiss sheet
    await tester.pumpAndSettle();

    // The Tasks tab has a visible entry into routines.
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    expect(find.text('Repeating tasks'), findsOneWidget);
    expect(find.text('1 active'), findsOneWidget);

    await unmount(tester, db);
  });

  testWidgets('a task can be made monthly on its day', (tester) async {
    final db = await pumpSignedIn(tester);
    await tester.enterText(find.byType(TextField), 'Pay rent');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay rent'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Monthly on the'));
    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('now repeats: monthly on the'), findsOneWidget);

    final r = (await tester.runAsync(() => db.select(db.recurrences).getSingle()))!;
    expect(r.frequency, 'monthly');
    expect(r.monthDay, DateTime.now().day);
    await unmount(tester, db);
  });

  testWidgets('routine editor offers Monthly with a day grid', (tester) async {
    final db = await pumpSignedIn(tester);
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repeating tasks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New routine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Invoice clients');
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    expect(find.text('M'), findsNothing, reason: 'weekday toggles hidden for monthly');
    await tester.tap(find.byTooltip('More apart')); // every 2 months
    await tester.pumpAndSettle();
    expect(find.text('months'), findsOneWidget);
    await tester.ensureVisible(find.text('28'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('28'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.textContaining('Every 2 months on the 28th'));
    expect(find.textContaining('Every 2 months on the 28th'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Every 2 months on the 28th'), findsOneWidget, reason: 'shown in the routines list');

    final r = (await tester.runAsync(() => db.select(db.recurrences).getSingle()))!;
    expect((r.frequency, r.monthDay, r.repeatInterval), ('monthly', 28, 2));
    await unmount(tester, db);
  });

  testWidgets('Custom… opens the routine editor prefilled for weekday picking', (tester) async {
    final db = await pumpSignedIn(tester);
    await tester.enterText(find.byType(TextField), 'Gym');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom…'));
    await tester.pumpAndSettle();

    expect(find.text('New routine'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Gym'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    // Weekday toggles and the every-N stepper are there.
    expect(find.text('M'), findsOneWidget);
    expect(find.byTooltip('More apart'), findsOneWidget);

    await tester.tap(find.byTooltip('More apart')); // every 2 weeks
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final routines = await tester.runAsync(() => db.select(db.recurrences).get());
    expect(routines!.single.repeatInterval, 2);
    final oneOff = await tester.runAsync(
        () => (db.select(db.tasks)..where((t) => t.recurrenceId.isNull() & t.deletedAt.isNull())).get());
    expect(oneOff, isEmpty, reason: 'original task replaced by the routine');

    await unmount(tester, db);
  });
}
