// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'source_control_watcher.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(sourceControlWatcher)
final sourceControlWatcherProvider = SourceControlWatcherProvider._();

final class SourceControlWatcherProvider
    extends
        $FunctionalProvider<
          SourceControlWatcher,
          SourceControlWatcher,
          SourceControlWatcher
        >
    with $Provider<SourceControlWatcher> {
  SourceControlWatcherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sourceControlWatcherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sourceControlWatcherHash();

  @$internal
  @override
  $ProviderElement<SourceControlWatcher> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SourceControlWatcher create(Ref ref) {
    return sourceControlWatcher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SourceControlWatcher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SourceControlWatcher>(value),
    );
  }
}

String _$sourceControlWatcherHash() =>
    r'd84112f3679f1fca0459d12ed250cfb81f6abb28';
