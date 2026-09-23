import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/app.dart';
import 'package:index_app/core/network/api.dart';
import 'package:index_app/core/network/token_store.dart';
import 'package:index_app/core/providers.dart';
import 'package:index_app/core/ui/app_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support.dart';

class FakePublicApi extends PublicApi {
  bool hasAccount = false;
  final calls = <String>[];

  @override
  Future<void> health(String serverUrl) async => calls.add('health $serverUrl');

  @override
  Future<bool> hasUser(String serverUrl) async => hasAccount;

  @override
  Future<AuthTokens> register(String serverUrl, String email, String password) async {
    calls.add('register $email');
    hasAccount = true;
    return const AuthTokens(accessToken: 'a', refreshToken: 'r');
  }

  @override
  Future<AuthTokens> login(String serverUrl, String email, String password) async =>
      const AuthTokens(accessToken: 'a', refreshToken: 'r');

  @override
  Future<void> logout(String serverUrl, String refreshToken) async => calls.add('logout $refreshToken');
}

/// Routes Dio requests to [FakeSyncServer] without real networking.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.server);

  final FakeSyncServer server;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body, Future<void>? cancel) async {
    if (options.path.endsWith('/sync')) {
      final resp = await server.handle((options.data as Map).cast<String, dynamic>());
      return ResponseBody.fromString(jsonEncode(resp), 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    return ResponseBody.fromString('{"error":{"code":"not_found","message":"nope"}}', 404,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('setup -> register -> Today -> quick capture syncs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = memoryDb();
    final public = FakePublicApi();
    final server = FakeSyncServer();
    final dio = Dio(BaseOptions(baseUrl: 'http://fake/api/v1'))..httpClientAdapter = FakeAdapter(server);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
        publicApiProvider.overrideWithValue(public),
        apiProvider.overrideWithValue(Api.withDio(dio)),
      ],
      child: const IndexApp(),
    ));
    await tester.pumpAndSettle();

    // Server setup.
    expect(find.text('Welcome to Index'), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);
    await tester.enterText(find.byType(TextField), '192.168.1.5:8080');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(public.calls, contains('health http://192.168.1.5:8080'));

    // No account yet: registration form.
    expect(find.text('Create your account'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'me@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'correct horse');
    await tester.enterText(find.widgetWithText(TextFormField, 'Confirm password'), 'correct horse');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(public.calls, contains('register me@example.com'));

    // Today, empty.
    expect(find.text('Nothing scheduled today'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Water plants');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Water plants'), findsOneWidget);
    expect(find.text('0 of 1 done'), findsOneWidget);

    // Debounced sync pushes the new task.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final pushed = server.requests.expand((r) => (r['changes']['tasks'] as List)).toList();
    expect(pushed.map((t) => t['title']), contains('Water plants'));

    // Complete it.
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(find.text('1 of 1 done'), findsOneWidget);

    // Other tabs render.
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    expect(find.text('No learning plans yet'), findsOneWidget);
    await tester.tap(find.text('Tasks').last);
    await tester.pumpAndSettle();
    expect(find.text('Completed (1)'), findsOneWidget);
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('Water plants'), findsOneWidget);

    // Unmount (cancels sync timers), let pending queries in the fake-async
    // zone finish, then close the database.
    // History lists the completed task.
    await tester.tap(find.byTooltip('History'));
    await tester.pumpAndSettle();
    expect(find.text('Water plants'), findsOneWidget);
    expect(find.text('day streak'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Create a daily routine; its occurrence for today appears on Today.
    await tester.tap(find.byTooltip('Routines'));
    await tester.pumpAndSettle();
    expect(find.text('No routines yet'), findsOneWidget);
    await tester.tap(find.text('New routine'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Stretch');
    await tester.tap(find.text('Every day'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Stretch'), findsOneWidget);
    expect(find.textContaining('Every day'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Stretch'), findsOneWidget, reason: "today's occurrence in the day list");

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Stretch'), findsOneWidget);

    // Signing out ends the session on the server and returns to login.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign out'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(public.calls, contains('logout r'));
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });
}
