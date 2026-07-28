// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'push_coordinator.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PushCoordinator)
final pushCoordinatorProvider = PushCoordinatorProvider._();

final class PushCoordinatorProvider
    extends $AsyncNotifierProvider<PushCoordinator, PushCoordinationState> {
  PushCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pushCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pushCoordinatorHash();

  @$internal
  @override
  PushCoordinator create() => PushCoordinator();
}

String _$pushCoordinatorHash() => r'6ad87ece47e051b780e1028ea7bb84fec1cb64c9';

abstract class _$PushCoordinator extends $AsyncNotifier<PushCoordinationState> {
  FutureOr<PushCoordinationState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<PushCoordinationState>, PushCoordinationState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<PushCoordinationState>,
                PushCoordinationState
              >,
              AsyncValue<PushCoordinationState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
