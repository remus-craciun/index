// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the server address and login state and drives app routing.

@ProviderFor(SessionController)
final sessionControllerProvider = SessionControllerProvider._();

/// Owns the server address and login state and drives app routing.
final class SessionControllerProvider
    extends $AsyncNotifierProvider<SessionController, Session> {
  /// Owns the server address and login state and drives app routing.
  SessionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionControllerHash();

  @$internal
  @override
  SessionController create() => SessionController();
}

String _$sessionControllerHash() => r'b0014b380ee2bdf3a5f91b86b99197df53c7bb29';

/// Owns the server address and login state and drives app routing.

abstract class _$SessionController extends $AsyncNotifier<Session> {
  FutureOr<Session> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Session>, Session>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Session>, Session>,
              AsyncValue<Session>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
