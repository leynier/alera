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
    r'fbdf24cf91a1be0c96dc33add8e17d6ae2c65aed';

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
