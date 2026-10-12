// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_automation_destinations.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Agent tabs of [workspaceId] whose native conversation can be resumed.

@ProviderFor(mobileAutomationConversationTabs)
final mobileAutomationConversationTabsProvider =
    MobileAutomationConversationTabsFamily._();

/// Agent tabs of [workspaceId] whose native conversation can be resumed.

final class MobileAutomationConversationTabsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<WorkspaceTabSummary>>,
          List<WorkspaceTabSummary>,
          FutureOr<List<WorkspaceTabSummary>>
        >
    with
        $FutureModifier<List<WorkspaceTabSummary>>,
        $FutureProvider<List<WorkspaceTabSummary>> {
  /// Agent tabs of [workspaceId] whose native conversation can be resumed.
  MobileAutomationConversationTabsProvider._({
    required MobileAutomationConversationTabsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationConversationTabsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationConversationTabsHash();

  @override
  String toString() {
    return r'mobileAutomationConversationTabsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<WorkspaceTabSummary>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<WorkspaceTabSummary>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return mobileAutomationConversationTabs(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationConversationTabsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationConversationTabsHash() =>
    r'b5f464709fa593beb3022e04c3abe9ad13a96b05';

/// Agent tabs of [workspaceId] whose native conversation can be resumed.

final class MobileAutomationConversationTabsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<WorkspaceTabSummary>>,
          (String, String)
        > {
  MobileAutomationConversationTabsFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationConversationTabsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Agent tabs of [workspaceId] whose native conversation can be resumed.

  MobileAutomationConversationTabsProvider call(
    String hostId,
    String workspaceId,
  ) => MobileAutomationConversationTabsProvider._(
    argument: (hostId, workspaceId),
    from: this,
  );

  @override
  String toString() => r'mobileAutomationConversationTabsProvider';
}

/// Every resumable conversation on the host, for the Running Agents section
/// of the destination sheet. A workspace whose tabs fail to load is skipped.

@ProviderFor(mobileAutomationConversations)
final mobileAutomationConversationsProvider =
    MobileAutomationConversationsFamily._();

/// Every resumable conversation on the host, for the Running Agents section
/// of the destination sheet. A workspace whose tabs fail to load is skipped.

final class MobileAutomationConversationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MobileAutomationConversation>>,
          List<MobileAutomationConversation>,
          FutureOr<List<MobileAutomationConversation>>
        >
    with
        $FutureModifier<List<MobileAutomationConversation>>,
        $FutureProvider<List<MobileAutomationConversation>> {
  /// Every resumable conversation on the host, for the Running Agents section
  /// of the destination sheet. A workspace whose tabs fail to load is skipped.
  MobileAutomationConversationsProvider._({
    required MobileAutomationConversationsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationConversationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationConversationsHash();

  @override
  String toString() {
    return r'mobileAutomationConversationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<MobileAutomationConversation>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<MobileAutomationConversation>> create(Ref ref) {
    final argument = this.argument as String;
    return mobileAutomationConversations(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationConversationsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationConversationsHash() =>
    r'4333e4be1cc327ade96c2d486c1d07420188afc6';

/// Every resumable conversation on the host, for the Running Agents section
/// of the destination sheet. A workspace whose tabs fail to load is skipped.

final class MobileAutomationConversationsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<MobileAutomationConversation>>,
          String
        > {
  MobileAutomationConversationsFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationConversationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every resumable conversation on the host, for the Running Agents section
  /// of the destination sheet. A workspace whose tabs fail to load is skipped.

  MobileAutomationConversationsProvider call(String hostId) =>
      MobileAutomationConversationsProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationConversationsProvider';
}

/// Registered project folders of a project, from the runtime checkout list.

@ProviderFor(mobileAutomationProjectFolders)
final mobileAutomationProjectFoldersProvider =
    MobileAutomationProjectFoldersFamily._();

/// Registered project folders of a project, from the runtime checkout list.

final class MobileAutomationProjectFoldersProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<({String hostId, String path})>>,
          List<({String hostId, String path})>,
          FutureOr<List<({String hostId, String path})>>
        >
    with
        $FutureModifier<List<({String hostId, String path})>>,
        $FutureProvider<List<({String hostId, String path})>> {
  /// Registered project folders of a project, from the runtime checkout list.
  MobileAutomationProjectFoldersProvider._({
    required MobileAutomationProjectFoldersFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationProjectFoldersProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationProjectFoldersHash();

  @override
  String toString() {
    return r'mobileAutomationProjectFoldersProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<({String hostId, String path})>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<({String hostId, String path})>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return mobileAutomationProjectFolders(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationProjectFoldersProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationProjectFoldersHash() =>
    r'eecc75510ec5db80b2491c96bd5909087392b3c5';

/// Registered project folders of a project, from the runtime checkout list.

final class MobileAutomationProjectFoldersFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<({String hostId, String path})>>,
          (String, String)
        > {
  MobileAutomationProjectFoldersFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationProjectFoldersProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Registered project folders of a project, from the runtime checkout list.

  MobileAutomationProjectFoldersProvider call(
    String hostId,
    String projectId,
  ) => MobileAutomationProjectFoldersProvider._(
    argument: (hostId, projectId),
    from: this,
  );

  @override
  String toString() => r'mobileAutomationProjectFoldersProvider';
}

@ProviderFor(mobileAutomationProjectBranches)
final mobileAutomationProjectBranchesProvider =
    MobileAutomationProjectBranchesFamily._();

final class MobileAutomationProjectBranchesProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileAutomationProjectBranches>,
          MobileAutomationProjectBranches,
          FutureOr<MobileAutomationProjectBranches>
        >
    with
        $FutureModifier<MobileAutomationProjectBranches>,
        $FutureProvider<MobileAutomationProjectBranches> {
  MobileAutomationProjectBranchesProvider._({
    required MobileAutomationProjectBranchesFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationProjectBranchesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationProjectBranchesHash();

  @override
  String toString() {
    return r'mobileAutomationProjectBranchesProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<MobileAutomationProjectBranches> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileAutomationProjectBranches> create(Ref ref) {
    final argument = this.argument as (String, String);
    return mobileAutomationProjectBranches(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationProjectBranchesProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationProjectBranchesHash() =>
    r'714462611b1d29e8c8f19eac072ff133235c8a09';

final class MobileAutomationProjectBranchesFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<MobileAutomationProjectBranches>,
          (String, String)
        > {
  MobileAutomationProjectBranchesFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationProjectBranchesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAutomationProjectBranchesProvider call(
    String hostId,
    String projectId,
  ) => MobileAutomationProjectBranchesProvider._(
    argument: (hostId, projectId),
    from: this,
  );

  @override
  String toString() => r'mobileAutomationProjectBranchesProvider';
}
