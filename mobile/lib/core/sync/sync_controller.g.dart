// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Schedules background sync while logged in: at startup, shortly after
/// local edits, when the app resumes, when connectivity returns, and every
/// few minutes.

@ProviderFor(SyncController)
final syncControllerProvider = SyncControllerProvider._();

/// Schedules background sync while logged in: at startup, shortly after
/// local edits, when the app resumes, when connectivity returns, and every
/// few minutes.
final class SyncControllerProvider
    extends $NotifierProvider<SyncController, SyncStatus> {
  /// Schedules background sync while logged in: at startup, shortly after
  /// local edits, when the app resumes, when connectivity returns, and every
  /// few minutes.
  SyncControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncControllerHash();

  @$internal
  @override
  SyncController create() => SyncController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncStatus>(value),
    );
  }
}

String _$syncControllerHash() => r'54d74d1b1ea151ec5cffe0d57decafb28270beb1';

/// Schedules background sync while logged in: at startup, shortly after
/// local edits, when the app resumes, when connectivity returns, and every
/// few minutes.

abstract class _$SyncController extends $Notifier<SyncStatus> {
  SyncStatus build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SyncStatus, SyncStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SyncStatus, SyncStatus>,
              SyncStatus,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
