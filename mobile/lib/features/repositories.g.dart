// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'repositories.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(tasksRepository)
final tasksRepositoryProvider = TasksRepositoryProvider._();

final class TasksRepositoryProvider
    extends
        $FunctionalProvider<TasksRepository, TasksRepository, TasksRepository>
    with $Provider<TasksRepository> {
  TasksRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'tasksRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$tasksRepositoryHash();

  @$internal
  @override
  $ProviderElement<TasksRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TasksRepository create(Ref ref) {
    return tasksRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TasksRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TasksRepository>(value),
    );
  }
}

String _$tasksRepositoryHash() => r'b7b5d8470c7c152590871561a71b4b835eb4facf';

@ProviderFor(plansRepository)
final plansRepositoryProvider = PlansRepositoryProvider._();

final class PlansRepositoryProvider
    extends
        $FunctionalProvider<PlansRepository, PlansRepository, PlansRepository>
    with $Provider<PlansRepository> {
  PlansRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'plansRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$plansRepositoryHash();

  @$internal
  @override
  $ProviderElement<PlansRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PlansRepository create(Ref ref) {
    return plansRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PlansRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PlansRepository>(value),
    );
  }
}

String _$plansRepositoryHash() => r'08d02ea94d759f867c9cef6aa4b9c20d8ebe5347';

/// Kept alive: AI calls take up to a minute, and the repository calls back
/// into the sync controller afterwards. An auto-disposed provider would be
/// gone by then ("Cannot use the Ref ... after it has been disposed").

@ProviderFor(aiRepository)
final aiRepositoryProvider = AiRepositoryProvider._();

/// Kept alive: AI calls take up to a minute, and the repository calls back
/// into the sync controller afterwards. An auto-disposed provider would be
/// gone by then ("Cannot use the Ref ... after it has been disposed").

final class AiRepositoryProvider
    extends $FunctionalProvider<AiRepository, AiRepository, AiRepository>
    with $Provider<AiRepository> {
  /// Kept alive: AI calls take up to a minute, and the repository calls back
  /// into the sync controller afterwards. An auto-disposed provider would be
  /// gone by then ("Cannot use the Ref ... after it has been disposed").
  AiRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'aiRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$aiRepositoryHash();

  @$internal
  @override
  $ProviderElement<AiRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AiRepository create(Ref ref) {
    return aiRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AiRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AiRepository>(value),
    );
  }
}

String _$aiRepositoryHash() => r'916dd7272771c0fc8f22f199177ae2207d9f5637';

/// The current local date; updates at midnight so Today rolls over.

@ProviderFor(CurrentDay)
final currentDayProvider = CurrentDayProvider._();

/// The current local date; updates at midnight so Today rolls over.
final class CurrentDayProvider extends $NotifierProvider<CurrentDay, String> {
  /// The current local date; updates at midnight so Today rolls over.
  CurrentDayProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentDayProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentDayHash();

  @$internal
  @override
  CurrentDay create() => CurrentDay();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$currentDayHash() => r'60974b0c5e30f441f7130de773dca46f45528d6d';

/// The current local date; updates at midnight so Today rolls over.

abstract class _$CurrentDay extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(todayEntries)
final todayEntriesProvider = TodayEntriesProvider._();

final class TodayEntriesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TodayEntry>>,
          List<TodayEntry>,
          Stream<List<TodayEntry>>
        >
    with $FutureModifier<List<TodayEntry>>, $StreamProvider<List<TodayEntry>> {
  TodayEntriesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'todayEntriesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$todayEntriesHash();

  @$internal
  @override
  $StreamProviderElement<List<TodayEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TodayEntry>> create(Ref ref) {
    return todayEntries(ref);
  }
}

String _$todayEntriesHash() => r'21f8ad371a773c190acb5a0511a045cfcd57d687';

@ProviderFor(inboxTasks)
final inboxTasksProvider = InboxTasksProvider._();

final class InboxTasksProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TaskRow>>,
          List<TaskRow>,
          Stream<List<TaskRow>>
        >
    with $FutureModifier<List<TaskRow>>, $StreamProvider<List<TaskRow>> {
  InboxTasksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inboxTasksProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inboxTasksHash();

  @$internal
  @override
  $StreamProviderElement<List<TaskRow>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TaskRow>> create(Ref ref) {
    return inboxTasks(ref);
  }
}

String _$inboxTasksHash() => r'e34fc1bb1e7a639fb3d67af24662ede9acbfe323';

@ProviderFor(planSummaries)
final planSummariesProvider = PlanSummariesProvider._();

final class PlanSummariesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<PlanSummary>>,
          List<PlanSummary>,
          Stream<List<PlanSummary>>
        >
    with
        $FutureModifier<List<PlanSummary>>,
        $StreamProvider<List<PlanSummary>> {
  PlanSummariesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'planSummariesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$planSummariesHash();

  @$internal
  @override
  $StreamProviderElement<List<PlanSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<PlanSummary>> create(Ref ref) {
    return planSummaries(ref);
  }
}

String _$planSummariesHash() => r'154065a88fc159e73cee09e2ca69d13ea9aff5c6';

@ProviderFor(planDetail)
final planDetailProvider = PlanDetailFamily._();

final class PlanDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<PlanDetail?>,
          PlanDetail?,
          Stream<PlanDetail?>
        >
    with $FutureModifier<PlanDetail?>, $StreamProvider<PlanDetail?> {
  PlanDetailProvider._({
    required PlanDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'planDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$planDetailHash();

  @override
  String toString() {
    return r'planDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<PlanDetail?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<PlanDetail?> create(Ref ref) {
    final argument = this.argument as String;
    return planDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is PlanDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$planDetailHash() => r'0f13334d8ddfaf9864d0ba7e3c9fdd0c2fa9fb08';

final class PlanDetailFamily extends $Family
    with $FunctionalFamilyOverride<Stream<PlanDetail?>, String> {
  PlanDetailFamily._()
    : super(
        retry: null,
        name: r'planDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  PlanDetailProvider call(String id) =>
      PlanDetailProvider._(argument: id, from: this);

  @override
  String toString() => r'planDetailProvider';
}

@ProviderFor(routinesRepository)
final routinesRepositoryProvider = RoutinesRepositoryProvider._();

final class RoutinesRepositoryProvider
    extends
        $FunctionalProvider<
          RoutinesRepository,
          RoutinesRepository,
          RoutinesRepository
        >
    with $Provider<RoutinesRepository> {
  RoutinesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routinesRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routinesRepositoryHash();

  @$internal
  @override
  $ProviderElement<RoutinesRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RoutinesRepository create(Ref ref) {
    return routinesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoutinesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoutinesRepository>(value),
    );
  }
}

String _$routinesRepositoryHash() =>
    r'9507dad150ac785fa82362368aee83a5faaef73d';

@ProviderFor(routines)
final routinesProvider = RoutinesProvider._();

final class RoutinesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RecurrenceRow>>,
          List<RecurrenceRow>,
          Stream<List<RecurrenceRow>>
        >
    with
        $FutureModifier<List<RecurrenceRow>>,
        $StreamProvider<List<RecurrenceRow>> {
  RoutinesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routinesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routinesHash();

  @$internal
  @override
  $StreamProviderElement<List<RecurrenceRow>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<RecurrenceRow>> create(Ref ref) {
    return routines(ref);
  }
}

String _$routinesHash() => r'3e8b75089ad356b360d3c06f73f8e9cc3bdfac6b';

@ProviderFor(routine)
final routineProvider = RoutineFamily._();

final class RoutineProvider
    extends
        $FunctionalProvider<
          AsyncValue<RecurrenceRow?>,
          RecurrenceRow?,
          Stream<RecurrenceRow?>
        >
    with $FutureModifier<RecurrenceRow?>, $StreamProvider<RecurrenceRow?> {
  RoutineProvider._({
    required RoutineFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'routineProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$routineHash();

  @override
  String toString() {
    return r'routineProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<RecurrenceRow?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<RecurrenceRow?> create(Ref ref) {
    final argument = this.argument as String;
    return routine(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RoutineProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$routineHash() => r'0e5eef5184f267487291d7b7380b30abcdb20559';

final class RoutineFamily extends $Family
    with $FunctionalFamilyOverride<Stream<RecurrenceRow?>, String> {
  RoutineFamily._()
    : super(
        retry: null,
        name: r'routineProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  RoutineProvider call(String id) =>
      RoutineProvider._(argument: id, from: this);

  @override
  String toString() => r'routineProvider';
}

/// Keeps routine occurrences generated: at startup, whenever routines
/// change (locally or via sync) and when the day rolls over.

@ProviderFor(routineGenerator)
final routineGeneratorProvider = RoutineGeneratorProvider._();

/// Keeps routine occurrences generated: at startup, whenever routines
/// change (locally or via sync) and when the day rolls over.

final class RoutineGeneratorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Keeps routine occurrences generated: at startup, whenever routines
  /// change (locally or via sync) and when the day rolls over.
  RoutineGeneratorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'routineGeneratorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$routineGeneratorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return routineGenerator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$routineGeneratorHash() => r'9b5baee364018dd38acf161cfa325e8ec99f7a67';

@ProviderFor(tasksInRange)
final tasksInRangeProvider = TasksInRangeFamily._();

final class TasksInRangeProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TodayEntry>>,
          List<TodayEntry>,
          Stream<List<TodayEntry>>
        >
    with $FutureModifier<List<TodayEntry>>, $StreamProvider<List<TodayEntry>> {
  TasksInRangeProvider._({
    required TasksInRangeFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'tasksInRangeProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$tasksInRangeHash();

  @override
  String toString() {
    return r'tasksInRangeProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<List<TodayEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TodayEntry>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return tasksInRange(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is TasksInRangeProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$tasksInRangeHash() => r'0c71941e1ce178a14c93d42133b2d60d186c9c63';

final class TasksInRangeFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<TodayEntry>>, (String, String)> {
  TasksInRangeFamily._()
    : super(
        retry: null,
        name: r'tasksInRangeProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  TasksInRangeProvider call(String from, String to) =>
      TasksInRangeProvider._(argument: (from, to), from: this);

  @override
  String toString() => r'tasksInRangeProvider';
}

@ProviderFor(completedTasks)
final completedTasksProvider = CompletedTasksProvider._();

final class CompletedTasksProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<TodayEntry>>,
          List<TodayEntry>,
          Stream<List<TodayEntry>>
        >
    with $FutureModifier<List<TodayEntry>>, $StreamProvider<List<TodayEntry>> {
  CompletedTasksProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'completedTasksProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$completedTasksHash();

  @$internal
  @override
  $StreamProviderElement<List<TodayEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<TodayEntry>> create(Ref ref) {
    return completedTasks(ref);
  }
}

String _$completedTasksHash() => r'12a4de8db97598b3fd0e9fd924a1387f5420e23e';

@ProviderFor(notificationService)
final notificationServiceProvider = NotificationServiceProvider._();

final class NotificationServiceProvider
    extends
        $FunctionalProvider<
          NotificationService,
          NotificationService,
          NotificationService
        >
    with $Provider<NotificationService> {
  NotificationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'notificationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$notificationServiceHash();

  @$internal
  @override
  $ProviderElement<NotificationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  NotificationService create(Ref ref) {
    return notificationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NotificationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NotificationService>(value),
    );
  }
}

String _$notificationServiceHash() =>
    r'585c1e42ea844e71a2b76b80b165adfe2c5c8529';

/// When reminders fire for tasks without a start time (HH:MM).

@ProviderFor(DefaultReminderTime)
final defaultReminderTimeProvider = DefaultReminderTimeProvider._();

/// When reminders fire for tasks without a start time (HH:MM).
final class DefaultReminderTimeProvider
    extends $NotifierProvider<DefaultReminderTime, String> {
  /// When reminders fire for tasks without a start time (HH:MM).
  DefaultReminderTimeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'defaultReminderTimeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$defaultReminderTimeHash();

  @$internal
  @override
  DefaultReminderTime create() => DefaultReminderTime();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String>(value),
    );
  }
}

String _$defaultReminderTimeHash() =>
    r'2a2592d925ae597ace0fe3a52495ec3b075de7ac';

/// When reminders fire for tasks without a start time (HH:MM).

abstract class _$DefaultReminderTime extends $Notifier<String> {
  String build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String, String>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String, String>,
              String,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Mirrors reminders of the next two weeks into scheduled notifications.

@ProviderFor(reminderScheduler)
final reminderSchedulerProvider = ReminderSchedulerProvider._();

/// Mirrors reminders of the next two weeks into scheduled notifications.

final class ReminderSchedulerProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  /// Mirrors reminders of the next two weeks into scheduled notifications.
  ReminderSchedulerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reminderSchedulerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reminderSchedulerHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return reminderScheduler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$reminderSchedulerHash() => r'795c7f4954806397b7d04833825979ce6b23de82';
