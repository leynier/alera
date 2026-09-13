// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'linked_issue_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(linkedIssueRepository)
final linkedIssueRepositoryProvider = LinkedIssueRepositoryProvider._();

final class LinkedIssueRepositoryProvider
    extends
        $FunctionalProvider<
          LinkedIssueRepository,
          LinkedIssueRepository,
          LinkedIssueRepository
        >
    with $Provider<LinkedIssueRepository> {
  LinkedIssueRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'linkedIssueRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$linkedIssueRepositoryHash();

  @$internal
  @override
  $ProviderElement<LinkedIssueRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LinkedIssueRepository create(Ref ref) {
    return linkedIssueRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LinkedIssueRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LinkedIssueRepository>(value),
    );
  }
}

String _$linkedIssueRepositoryHash() =>
    r'e7f227f24611154b71384fe72b0a3a8b31071d55';

/// Host support plus every linked issue. Watching it also keeps the cached
/// metadata fresh while the window is visible.

@ProviderFor(linkedIssueSnapshot)
final linkedIssueSnapshotProvider = LinkedIssueSnapshotProvider._();

/// Host support plus every linked issue. Watching it also keeps the cached
/// metadata fresh while the window is visible.

final class LinkedIssueSnapshotProvider
    extends
        $FunctionalProvider<
          AsyncValue<LinkedIssueSnapshot>,
          LinkedIssueSnapshot,
          Stream<LinkedIssueSnapshot>
        >
    with
        $FutureModifier<LinkedIssueSnapshot>,
        $StreamProvider<LinkedIssueSnapshot> {
  /// Host support plus every linked issue. Watching it also keeps the cached
  /// metadata fresh while the window is visible.
  LinkedIssueSnapshotProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'linkedIssueSnapshotProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$linkedIssueSnapshotHash();

  @$internal
  @override
  $StreamProviderElement<LinkedIssueSnapshot> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<LinkedIssueSnapshot> create(Ref ref) {
    return linkedIssueSnapshot(ref);
  }
}

String _$linkedIssueSnapshotHash() =>
    r'9f35512bee3bb7b44ce41e3651780f0004d96f96';

/// Whether the connected host advertises linked issues. False until the first
/// snapshot arrives, so no control is offered that an older host would reject.

@ProviderFor(linkedIssuesSupported)
final linkedIssuesSupportedProvider = LinkedIssuesSupportedProvider._();

/// Whether the connected host advertises linked issues. False until the first
/// snapshot arrives, so no control is offered that an older host would reject.

final class LinkedIssuesSupportedProvider
    extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the connected host advertises linked issues. False until the first
  /// snapshot arrives, so no control is offered that an older host would reject.
  LinkedIssuesSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'linkedIssuesSupportedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$linkedIssuesSupportedHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return linkedIssuesSupported(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$linkedIssuesSupportedHash() =>
    r'62064df8469fc9c8d2b7599a57a9175d6019bd6c';

/// The linked issue of one workspace, or null. Selects from the shared
/// snapshot so a sidebar with many rows costs one host request per change;
/// a row rebuilds only when its own link changes.

@ProviderFor(workspaceLinkedIssue)
final workspaceLinkedIssueProvider = WorkspaceLinkedIssueFamily._();

/// The linked issue of one workspace, or null. Selects from the shared
/// snapshot so a sidebar with many rows costs one host request per change;
/// a row rebuilds only when its own link changes.

final class WorkspaceLinkedIssueProvider
    extends $FunctionalProvider<LinkedIssue?, LinkedIssue?, LinkedIssue?>
    with $Provider<LinkedIssue?> {
  /// The linked issue of one workspace, or null. Selects from the shared
  /// snapshot so a sidebar with many rows costs one host request per change;
  /// a row rebuilds only when its own link changes.
  WorkspaceLinkedIssueProvider._({
    required WorkspaceLinkedIssueFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'workspaceLinkedIssueProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$workspaceLinkedIssueHash();

  @override
  String toString() {
    return r'workspaceLinkedIssueProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<LinkedIssue?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  LinkedIssue? create(Ref ref) {
    final argument = this.argument as String;
    return workspaceLinkedIssue(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LinkedIssue? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LinkedIssue?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WorkspaceLinkedIssueProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$workspaceLinkedIssueHash() =>
    r'2d379fe9960cf621c66a6a1c36cd5a1745980d6b';

/// The linked issue of one workspace, or null. Selects from the shared
/// snapshot so a sidebar with many rows costs one host request per change;
/// a row rebuilds only when its own link changes.

final class WorkspaceLinkedIssueFamily extends $Family
    with $FunctionalFamilyOverride<LinkedIssue?, String> {
  WorkspaceLinkedIssueFamily._()
    : super(
        retry: null,
        name: r'workspaceLinkedIssueProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The linked issue of one workspace, or null. Selects from the shared
  /// snapshot so a sidebar with many rows costs one host request per change;
  /// a row rebuilds only when its own link changes.

  WorkspaceLinkedIssueProvider call(String workspaceId) =>
      WorkspaceLinkedIssueProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'workspaceLinkedIssueProvider';
}
