// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_focus_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Opens the stream of workspace ids the runtime asks this app to focus
/// (`alera workspace focus`). Every event counts, including a repeat of the
/// previous id, so this is a plain stream rather than a stream provider.

@ProviderFor(workspaceFocusRequestSource)
final workspaceFocusRequestSourceProvider =
    WorkspaceFocusRequestSourceProvider._();

/// Opens the stream of workspace ids the runtime asks this app to focus
/// (`alera workspace focus`). Every event counts, including a repeat of the
/// previous id, so this is a plain stream rather than a stream provider.

final class WorkspaceFocusRequestSourceProvider
    extends
        $FunctionalProvider<
          Stream<String> Function(),
          Stream<String> Function(),
          Stream<String> Function()
        >
    with $Provider<Stream<String> Function()> {
  /// Opens the stream of workspace ids the runtime asks this app to focus
  /// (`alera workspace focus`). Every event counts, including a repeat of the
  /// previous id, so this is a plain stream rather than a stream provider.
  WorkspaceFocusRequestSourceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceFocusRequestSourceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceFocusRequestSourceHash();

  @$internal
  @override
  $ProviderElement<Stream<String> Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Stream<String> Function() create(Ref ref) {
    return workspaceFocusRequestSource(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Stream<String> Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Stream<String> Function()>(value),
    );
  }
}

String _$workspaceFocusRequestSourceHash() =>
    r'dde650478baa6fd4f969b7b0fefaa6a28b5d43fa';

@ProviderFor(workspaceFocusRequestCoordinator)
final workspaceFocusRequestCoordinatorProvider =
    WorkspaceFocusRequestCoordinatorProvider._();

final class WorkspaceFocusRequestCoordinatorProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  WorkspaceFocusRequestCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'workspaceFocusRequestCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$workspaceFocusRequestCoordinatorHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return workspaceFocusRequestCoordinator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$workspaceFocusRequestCoordinatorHash() =>
    r'4e02dffcc4effecdc3fb1e5cee91b13a6dd3a750';
