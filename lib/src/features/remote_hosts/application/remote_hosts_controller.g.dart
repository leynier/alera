// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_hosts_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Every remote host with one status each, merged from the stored targets,
/// their links and the install progress this session has seen, plus the
/// actions the Remote Hosts surfaces run.

@ProviderFor(RemoteHostsController)
final remoteHostsControllerProvider = RemoteHostsControllerProvider._();

/// Every remote host with one status each, merged from the stored targets,
/// their links and the install progress this session has seen, plus the
/// actions the Remote Hosts surfaces run.
final class RemoteHostsControllerProvider
    extends $NotifierProvider<RemoteHostsController, RemoteHostsState> {
  /// Every remote host with one status each, merged from the stored targets,
  /// their links and the install progress this session has seen, plus the
  /// actions the Remote Hosts surfaces run.
  RemoteHostsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'remoteHostsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$remoteHostsControllerHash();

  @$internal
  @override
  RemoteHostsController create() => RemoteHostsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RemoteHostsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RemoteHostsState>(value),
    );
  }
}

String _$remoteHostsControllerHash() =>
    r'27d0a441615bafdbf861950cb408ba321e211c3c';

/// Every remote host with one status each, merged from the stored targets,
/// their links and the install progress this session has seen, plus the
/// actions the Remote Hosts surfaces run.

abstract class _$RemoteHostsController extends $Notifier<RemoteHostsState> {
  RemoteHostsState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<RemoteHostsState, RemoteHostsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RemoteHostsState, RemoteHostsState>,
              RemoteHostsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
