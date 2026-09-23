import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/app.dart';
import 'package:index_app/core/network/api.dart';
import 'package:index_app/core/network/token_store.dart';
import 'package:index_app/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support.dart';

/// Answers /sync like the server and /ai/decompose-plan after a delay, the
/// way a real model call takes a while.
class SlowAiAdapter implements HttpClientAdapter {
  final sync = FakeSyncServer();

  static const _ts = '2026-03-01T10:00:00.000Z';
  static final plan = {
    'id': '0192f7a0-0000-7000-8000-000000000001',
    'title': 'Distributed Go',
    'description': 'Six weeks',
    'target_date': '2026-04-12',
    'status': 'active',
    'created_at': _ts,
    'updated_at': _ts,
    'deleted_at': null,
    'milestones': [
      {
        'id': '0192f7a0-0000-7000-8000-000000000002',
        'plan_id': '0192f7a0-0000-7000-8000-000000000001',
        'title': 'Foundations',
        'order_index': 1,
        'status': 'active',
        'created_at': _ts,
        'updated_at': _ts,
        'deleted_at': null,
        'tasks': [
          {
            'id': '0192f7a0-0000-7000-8000-000000000003',
            'milestone_id': '0192f7a0-0000-7000-8000-000000000002',
            'title': 'Goroutines and channels',
            'notes': 'Tour of Go',
            'scheduled_date': '2026-03-02',
            'estimated_minutes': 45,
            'status': 'pending',
            'created_at': _ts,
            'updated_at': _ts,
            'deleted_at': null,
          },
        ],
      },
    ],
  };

  final revisions = <String>[];
  var applied = 0;

  static final proposal = {
    'summary': 'Swapped the intro task for a hands-on project.',
    'minutes_per_day': 45,
    'changes': [
      {'kind': 'task', 'action': 'removed', 'title': 'Goroutines and channels'},
      {'kind': 'task', 'action': 'added', 'title': 'Build a worker pool', 'detail': 'in Foundations'},
    ],
    'revision': {'title': 'Distributed Go', 'description': 'Six weeks', 'milestones': []},
  };

  /// The plan after applying: the original task is gone, a new one exists.
  static Map<String, dynamic> get revisedPlan {
    final p = jsonDecode(jsonEncode(plan)) as Map<String, dynamic>;
    final m = (p['milestones'] as List).first as Map<String, dynamic>;
    m['tasks'] = [
      {
        'id': '0192f7a0-0000-7000-8000-000000000009',
        'milestone_id': m['id'],
        'title': 'Build a worker pool',
        'notes': '',
        'scheduled_date': '2026-03-02',
        'estimated_minutes': 45,
        'status': 'pending',
        'created_at': '2026-03-01T11:00:00.000Z',
        'updated_at': '2026-03-01T11:00:00.000Z',
        'deleted_at': null,
      },
    ];
    return p;
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? body, Future<void>? cancel) async {
    final headers = {Headers.contentTypeHeader: [Headers.jsonContentType]};
    if (options.path.endsWith('/ai/decompose-plan')) {
      await Future<void>.delayed(const Duration(seconds: 5));
      return ResponseBody.fromString(jsonEncode(plan), 201, headers: headers);
    }
    if (options.path.endsWith('/ai/revise-plan')) {
      revisions.add((options.data as Map)['instruction'] as String);
      await Future<void>.delayed(const Duration(seconds: 2));
      return ResponseBody.fromString(jsonEncode(proposal), 200, headers: headers);
    }
    if (options.path.endsWith('/apply-revision')) {
      applied++;
      return ResponseBody.fromString(jsonEncode(revisedPlan), 200, headers: headers);
    }
    if (options.path.endsWith('/sync')) {
      final resp = await sync.handle((options.data as Map).cast<String, dynamic>());
      return ResponseBody.fromString(jsonEncode(resp), 200, headers: headers);
    }
    return ResponseBody.fromString('{"error":{"code":"not_found","message":"nope"}}', 404, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('generating a plan survives the slow AI call and opens the plan', (tester) async {
    // A phone-sized screen, so the whole form fits.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'server_url': 'http://fake', 'data_server_url': 'http://fake'});
    final prefs = await SharedPreferences.getInstance();
    final db = memoryDb();
    final dio = Dio(BaseOptions(baseUrl: 'http://fake/api/v1'))..httpClientAdapter = SlowAiAdapter();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()..write(const AuthTokens(accessToken: 'a', refreshToken: 'r'))),
        apiProvider.overrideWithValue(Api.withDio(dio)),
      ],
      child: const IndexApp(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate a plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'What do you want to learn?'), 'Learn distributed systems in Go');
    await tester.tap(find.text('Generate plan'));
    await tester.pump();
    expect(find.text('Designing your plan…'), findsOneWidget);

    // Let the fake model answer (and any provider disposal happen meanwhile).
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot use the Ref'), findsNothing);
    expect(find.text('Distributed Go'), findsOneWidget, reason: 'navigated to the new plan');
    expect(find.text('Goroutines and channels'), findsOneWidget);

    // Follow-up request: preview, then apply.
    final adapter = dio.httpClientAdapter as SlowAiAdapter;
    await tester.tap(find.text('Ask AI for changes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'What should change?'), 'Make it more hands-on');
    await tester.tap(find.text('Preview changes'));
    await tester.pump();
    expect(find.text('Working out the changes…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(adapter.revisions, ['Make it more hands-on']);
    expect(find.text('Swapped the intro task for a hands-on project.'), findsOneWidget);
    expect(find.textContaining('Build a worker pool'), findsOneWidget);
    expect(find.textContaining('re-spread from today at about 45m a day'), findsOneWidget);
    expect(adapter.applied, 0, reason: 'nothing stored before Apply');

    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(adapter.applied, 1);
    expect(find.text('Plan updated'), findsOneWidget);
    // The sheet stays open for a follow-up, listing what was applied.
    expect(find.text('Make it more hands-on'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Anything else?'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // The plan screen shows the revised tasks.
    expect(find.text('Build a worker pool'), findsOneWidget);
    expect(find.text('Goroutines and channels'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(db.close);
  });
}
