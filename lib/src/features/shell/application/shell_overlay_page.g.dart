// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shell_overlay_page.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(shellOverlayPage)
final shellOverlayPageProvider = ShellOverlayPageProvider._();

final class ShellOverlayPageProvider
    extends
        $FunctionalProvider<
          ShellOverlayPage,
          ShellOverlayPage,
          ShellOverlayPage
        >
    with $Provider<ShellOverlayPage> {
  ShellOverlayPageProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellOverlayPageProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellOverlayPageHash();

  @$internal
  @override
  $ProviderElement<ShellOverlayPage> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ShellOverlayPage create(Ref ref) {
    return shellOverlayPage(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ShellOverlayPage value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ShellOverlayPage>(value),
    );
  }
}

String _$shellOverlayPageHash() => r'c1e264715aeb9fa3da2b105e7514c0c8614ea819';
