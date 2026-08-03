// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cloud_accounts_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CloudAccountsController)
final cloudAccountsControllerProvider = CloudAccountsControllerProvider._();

final class CloudAccountsControllerProvider
    extends
        $AsyncNotifierProvider<
          CloudAccountsController,
          List<CloudAccountSession>
        > {
  CloudAccountsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cloudAccountsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cloudAccountsControllerHash();

  @$internal
  @override
  CloudAccountsController create() => CloudAccountsController();
}

String _$cloudAccountsControllerHash() =>
    r'a321ff4f588cb4486fce495e2e3f54ff04cb28ad';

abstract class _$CloudAccountsController
    extends $AsyncNotifier<List<CloudAccountSession>> {
  FutureOr<List<CloudAccountSession>> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<CloudAccountSession>>,
              List<CloudAccountSession>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<CloudAccountSession>>,
                List<CloudAccountSession>
              >,
              AsyncValue<List<CloudAccountSession>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
