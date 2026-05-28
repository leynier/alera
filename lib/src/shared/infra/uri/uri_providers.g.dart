// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'uri_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(externalUriLauncher)
final externalUriLauncherProvider = ExternalUriLauncherProvider._();

final class ExternalUriLauncherProvider
    extends
        $FunctionalProvider<
          ExternalUriLauncher,
          ExternalUriLauncher,
          ExternalUriLauncher
        >
    with $Provider<ExternalUriLauncher> {
  ExternalUriLauncherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'externalUriLauncherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$externalUriLauncherHash();

  @$internal
  @override
  $ProviderElement<ExternalUriLauncher> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ExternalUriLauncher create(Ref ref) {
    return externalUriLauncher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ExternalUriLauncher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ExternalUriLauncher>(value),
    );
  }
}

String _$externalUriLauncherHash() =>
    r'7afff7ab7df427105c8df09a38693d29552b2410';
