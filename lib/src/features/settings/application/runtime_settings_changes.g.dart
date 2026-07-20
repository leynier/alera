// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runtime_settings_changes.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(runtimeSettingsChanges)
final runtimeSettingsChangesProvider = RuntimeSettingsChangesProvider._();

final class RuntimeSettingsChangesProvider
    extends $FunctionalProvider<AsyncValue<void>, void, Stream<void>>
    with $FutureModifier<void>, $StreamProvider<void> {
  RuntimeSettingsChangesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'runtimeSettingsChangesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$runtimeSettingsChangesHash();

  @$internal
  @override
  $StreamProviderElement<void> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<void> create(Ref ref) {
    return runtimeSettingsChanges(ref);
  }
}

String _$runtimeSettingsChangesHash() =>
    r'2212d656004fe4280a2ac109ae6edcc253626130';
