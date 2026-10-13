// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workspace_git_snapshots.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(workspaceGitCatalog)
final workspaceGitCatalogProvider = WorkspaceGitCatalogFamily._();

final class WorkspaceGitCatalogProvider
    extends
        $FunctionalProvider<
          AsyncValue<WorkspaceGitCatalog>,
          WorkspaceGitCatalog,
          FutureOr<WorkspaceGitCatalog>
        >
    with
        $FutureModifier<WorkspaceGitCatalog>,
        $FutureProvider<WorkspaceGitCatalog> {
  WorkspaceGitCatalogProvider._({
    required WorkspaceGitCatalogFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceGitCatalogProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceGitCatalogHash();

  @override
  String toString() {
    return r'workspaceGitCatalogProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<WorkspaceGitCatalog> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<WorkspaceGitCatalog> create(Ref ref) {
    final argument = this.argument as String;
    return workspaceGitCatalog(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceGitCatalogProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceGitCatalogHash() =>
    r'9dcfd5b495dd317b626b2b5d762b2063a0d91497';

final class WorkspaceGitCatalogFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<WorkspaceGitCatalog>, String> {
  WorkspaceGitCatalogFamily._()
    : super(
        retry: null,
        name: r'workspaceGitCatalogProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceGitCatalogProvider call(String path) =>
      WorkspaceGitCatalogProvider._(argument: path, from: this);

  @override
  String toString() => r'workspaceGitCatalogProvider';
}

@ProviderFor(workspaceComparisonLoader)
final workspaceComparisonLoaderProvider = WorkspaceComparisonLoaderFamily._();

final class WorkspaceComparisonLoaderProvider
    extends
        $FunctionalProvider<
          WorkspaceComparisonLoader,
          WorkspaceComparisonLoader,
          WorkspaceComparisonLoader
        >
    with $Provider<WorkspaceComparisonLoader> {
  WorkspaceComparisonLoaderProvider._({
    required WorkspaceComparisonLoaderFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'workspaceComparisonLoaderProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceComparisonLoaderHash();

  @override
  String toString() {
    return r'workspaceComparisonLoaderProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $ProviderElement<WorkspaceComparisonLoader> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  WorkspaceComparisonLoader create(Ref ref) {
    final argument = this.argument as (String, String?);
    return workspaceComparisonLoader(ref, argument.$1, argument.$2);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(WorkspaceComparisonLoader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<WorkspaceComparisonLoader>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceComparisonLoaderProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceComparisonLoaderHash() =>
    r'1470951eae62c3da0755ef2513d983e933ba9aff';

final class WorkspaceComparisonLoaderFamily extends $Family
    with
        $FunctionalFamilyOverride<
          WorkspaceComparisonLoader,
          (String, String?)
        > {
  WorkspaceComparisonLoaderFamily._()
    : super(
        retry: null,
        name: r'workspaceComparisonLoaderProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceComparisonLoaderProvider call(String path, String? baseRef) =>
      WorkspaceComparisonLoaderProvider._(
        argument: (path, baseRef),
        from: this,
      );

  @override
  String toString() => r'workspaceComparisonLoaderProvider';
}

@ProviderFor(workspaceGitComparison)
final workspaceGitComparisonProvider = WorkspaceGitComparisonFamily._();

final class WorkspaceGitComparisonProvider
    extends
        $FunctionalProvider<
          AsyncValue<GitWorkspaceComparison>,
          GitWorkspaceComparison,
          FutureOr<GitWorkspaceComparison>
        >
    with
        $FutureModifier<GitWorkspaceComparison>,
        $FutureProvider<GitWorkspaceComparison> {
  WorkspaceGitComparisonProvider._({
    required WorkspaceGitComparisonFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'workspaceGitComparisonProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceGitComparisonHash();

  @override
  String toString() {
    return r'workspaceGitComparisonProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<GitWorkspaceComparison> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<GitWorkspaceComparison> create(Ref ref) {
    final argument = this.argument as (String, String?);
    return workspaceGitComparison(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceGitComparisonProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceGitComparisonHash() =>
    r'66822e9db6806e9f615ca9d113fe535f17d3c22c';

final class WorkspaceGitComparisonFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<GitWorkspaceComparison>,
          (String, String?)
        > {
  WorkspaceGitComparisonFamily._()
    : super(
        retry: null,
        name: r'workspaceGitComparisonProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  WorkspaceGitComparisonProvider call(String path, String? baseRef) =>
      WorkspaceGitComparisonProvider._(argument: (path, baseRef), from: this);

  @override
  String toString() => r'workspaceGitComparisonProvider';
}
