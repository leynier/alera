// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_automation_context.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(mobileAutomationContext)
final mobileAutomationContextProvider = MobileAutomationContextFamily._();

final class MobileAutomationContextProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileAutomationContext>,
          MobileAutomationContext,
          FutureOr<MobileAutomationContext>
        >
    with
        $FutureModifier<MobileAutomationContext>,
        $FutureProvider<MobileAutomationContext> {
  MobileAutomationContextProvider._({
    required MobileAutomationContextFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAutomationContextProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAutomationContextHash();

  @override
  String toString() {
    return r'mobileAutomationContextProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileAutomationContext> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileAutomationContext> create(Ref ref) {
    final argument = this.argument as String;
    return mobileAutomationContext(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAutomationContextProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAutomationContextHash() =>
    r'2937b6dc05321b03eb7a6c201cab023244fa6c7e';

final class MobileAutomationContextFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MobileAutomationContext>, String> {
  MobileAutomationContextFamily._()
    : super(
        retry: null,
        name: r'mobileAutomationContextProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAutomationContextProvider call(String hostId) =>
      MobileAutomationContextProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAutomationContextProvider';
}

/// Agent tabs whose native conversation can be resumed.

@ProviderFor(mobileAutomationConversationTabs)
final mobileAutomationConversationTabsProvider =
    MobileAutomationConversationTabsFamily._();

/// Agent tabs whose native conversation can be resumed.

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
  /// Agent tabs whose native conversation can be resumed.
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

/// Agent tabs whose native conversation can be resumed.

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

  /// Agent tabs whose native conversation can be resumed.

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
