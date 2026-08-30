// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paired_hosts_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PairedHostsController)
final pairedHostsControllerProvider = PairedHostsControllerProvider._();

final class PairedHostsControllerProvider
    extends
        $AsyncNotifierProvider<PairedHostsController, List<PairedHostProfile>> {
  PairedHostsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pairedHostsControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pairedHostsControllerHash();

  @$internal
  @override
  PairedHostsController create() => PairedHostsController();
}

String _$pairedHostsControllerHash() =>
    r'8f4ba28ebd7c4f16bcd75aefbd02669f582e9e8b';

abstract class _$PairedHostsController
    extends $AsyncNotifier<List<PairedHostProfile>> {
  FutureOr<List<PairedHostProfile>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<PairedHostProfile>>,
              List<PairedHostProfile>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<PairedHostProfile>>,
                List<PairedHostProfile>
              >,
              AsyncValue<List<PairedHostProfile>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(AvailableHosts)
final availableHostsProvider = AvailableHostsProvider._();

final class AvailableHostsProvider
    extends $AsyncNotifierProvider<AvailableHosts, List<PairedHostProfile>> {
  AvailableHostsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableHostsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableHostsHash();

  @$internal
  @override
  AvailableHosts create() => AvailableHosts();
}

String _$availableHostsHash() => r'18c242a48f6d092079092282b2898dbc42533dad';

abstract class _$AvailableHosts
    extends $AsyncNotifier<List<PairedHostProfile>> {
  FutureOr<List<PairedHostProfile>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<PairedHostProfile>>,
              List<PairedHostProfile>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<PairedHostProfile>>,
                List<PairedHostProfile>
              >,
              AsyncValue<List<PairedHostProfile>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
