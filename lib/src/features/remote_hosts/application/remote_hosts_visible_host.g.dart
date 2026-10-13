// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_hosts_visible_host.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The host Settings > Remote Hosts is showing, if any. Link toasts stay
/// quiet for it because its state is already on screen.

@ProviderFor(RemoteHostsVisibleHost)
final remoteHostsVisibleHostProvider = RemoteHostsVisibleHostProvider._();

/// The host Settings > Remote Hosts is showing, if any. Link toasts stay
/// quiet for it because its state is already on screen.
final class RemoteHostsVisibleHostProvider
    extends $NotifierProvider<RemoteHostsVisibleHost, String?> {
  /// The host Settings > Remote Hosts is showing, if any. Link toasts stay
  /// quiet for it because its state is already on screen.
  RemoteHostsVisibleHostProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'remoteHostsVisibleHostProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$remoteHostsVisibleHostHash();

  @$internal
  @override
  RemoteHostsVisibleHost create() => RemoteHostsVisibleHost();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$remoteHostsVisibleHostHash() =>
    r'bf904f875e3943b1cbadc5e05b3b332b8edd8fbf';

/// The host Settings > Remote Hosts is showing, if any. Link toasts stay
/// quiet for it because its state is already on screen.

abstract class _$RemoteHostsVisibleHost extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
