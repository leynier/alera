// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ssh_target_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(sshTargetRepository)
final sshTargetRepositoryProvider = SshTargetRepositoryProvider._();

final class SshTargetRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimeSshTargetRepository,
          RuntimeSshTargetRepository,
          RuntimeSshTargetRepository
        >
    with $Provider<RuntimeSshTargetRepository> {
  SshTargetRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sshTargetRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sshTargetRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimeSshTargetRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeSshTargetRepository create(Ref ref) {
    return sshTargetRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeSshTargetRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeSshTargetRepository>(value),
    );
  }
}

String _$sshTargetRepositoryHash() =>
    r'f00455c6dcfdfda442f77a426c68ea8d02daf212';

@ProviderFor(sshTargets)
final sshTargetsProvider = SshTargetsProvider._();

final class SshTargetsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<SshTarget>>,
          List<SshTarget>,
          Stream<List<SshTarget>>
        >
    with $FutureModifier<List<SshTarget>>, $StreamProvider<List<SshTarget>> {
  SshTargetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sshTargetsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sshTargetsHash();

  @$internal
  @override
  $StreamProviderElement<List<SshTarget>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<SshTarget>> create(Ref ref) {
    return sshTargets(ref);
  }
}

String _$sshTargetsHash() => r'ad231f96c8a6e8e6c087c33aafa0d842669d08c0';

@ProviderFor(sshTargetBootstrapProgress)
final sshTargetBootstrapProgressProvider =
    SshTargetBootstrapProgressProvider._();

final class SshTargetBootstrapProgressProvider
    extends
        $FunctionalProvider<
          AsyncValue<SshTargetBootstrapProgress>,
          SshTargetBootstrapProgress,
          Stream<SshTargetBootstrapProgress>
        >
    with
        $FutureModifier<SshTargetBootstrapProgress>,
        $StreamProvider<SshTargetBootstrapProgress> {
  SshTargetBootstrapProgressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sshTargetBootstrapProgressProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sshTargetBootstrapProgressHash();

  @$internal
  @override
  $StreamProviderElement<SshTargetBootstrapProgress> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<SshTargetBootstrapProgress> create(Ref ref) {
    return sshTargetBootstrapProgress(ref);
  }
}

String _$sshTargetBootstrapProgressHash() =>
    r'e9f439c965032784b33bc4731580217a16408bc0';
