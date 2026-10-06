// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_inbox_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The paired runtime as the Inbox screens see it. Rebuilds with every
/// reconnection, which reloads everything that depends on it.

@ProviderFor(mobileInboxClient)
final mobileInboxClientProvider = MobileInboxClientFamily._();

/// The paired runtime as the Inbox screens see it. Rebuilds with every
/// reconnection, which reloads everything that depends on it.

final class MobileInboxClientProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileInboxClient>,
          MobileInboxClient,
          FutureOr<MobileInboxClient>
        >
    with
        $FutureModifier<MobileInboxClient>,
        $FutureProvider<MobileInboxClient> {
  /// The paired runtime as the Inbox screens see it. Rebuilds with every
  /// reconnection, which reloads everything that depends on it.
  MobileInboxClientProvider._({
    required MobileInboxClientFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileInboxClientProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileInboxClientHash();

  @override
  String toString() {
    return r'mobileInboxClientProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileInboxClient> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileInboxClient> create(Ref ref) {
    final argument = this.argument as String;
    return mobileInboxClient(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileInboxClientProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileInboxClientHash() => r'53a80cc891b584f9a4c98844968ab0e5dde2131a';

/// The paired runtime as the Inbox screens see it. Rebuilds with every
/// reconnection, which reloads everything that depends on it.

final class MobileInboxClientFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MobileInboxClient>, String> {
  MobileInboxClientFamily._()
    : super(
        retry: null,
        name: r'mobileInboxClientProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The paired runtime as the Inbox screens see it. Rebuilds with every
  /// reconnection, which reloads everything that depends on it.

  MobileInboxClientProvider call(String hostId) =>
      MobileInboxClientProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileInboxClientProvider';
}

@ProviderFor(mobileInboxRepository)
final mobileInboxRepositoryProvider = MobileInboxRepositoryFamily._();

final class MobileInboxRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileRuntimeInboxRepository>,
          MobileRuntimeInboxRepository,
          FutureOr<MobileRuntimeInboxRepository>
        >
    with
        $FutureModifier<MobileRuntimeInboxRepository>,
        $FutureProvider<MobileRuntimeInboxRepository> {
  MobileInboxRepositoryProvider._({
    required MobileInboxRepositoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileInboxRepositoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileInboxRepositoryHash();

  @override
  String toString() {
    return r'mobileInboxRepositoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileRuntimeInboxRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileRuntimeInboxRepository> create(Ref ref) {
    final argument = this.argument as String;
    return mobileInboxRepository(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileInboxRepositoryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileInboxRepositoryHash() =>
    r'a8bc56b1cd02130292e35b7214db23a05e1e1d36';

final class MobileInboxRepositoryFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<MobileRuntimeInboxRepository>,
          String
        > {
  MobileInboxRepositoryFamily._()
    : super(
        retry: null,
        name: r'mobileInboxRepositoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileInboxRepositoryProvider call(String hostId) =>
      MobileInboxRepositoryProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileInboxRepositoryProvider';
}

/// Every inbox of the host with its counts.

@ProviderFor(MobileInboxSummary)
final mobileInboxSummaryProvider = MobileInboxSummaryFamily._();

/// Every inbox of the host with its counts.
final class MobileInboxSummaryProvider
    extends
        $AsyncNotifierProvider<MobileInboxSummary, List<InboxSummaryEntry>> {
  /// Every inbox of the host with its counts.
  MobileInboxSummaryProvider._({
    required MobileInboxSummaryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileInboxSummaryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileInboxSummaryHash();

  @override
  String toString() {
    return r'mobileInboxSummaryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileInboxSummary create() => MobileInboxSummary();

  @override
  bool operator ==(Object other) {
    return other is MobileInboxSummaryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileInboxSummaryHash() =>
    r'566e7743b445f34494e3959af10a170c1d20555d';

/// Every inbox of the host with its counts.

final class MobileInboxSummaryFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileInboxSummary,
          AsyncValue<List<InboxSummaryEntry>>,
          List<InboxSummaryEntry>,
          FutureOr<List<InboxSummaryEntry>>,
          String
        > {
  MobileInboxSummaryFamily._()
    : super(
        retry: null,
        name: r'mobileInboxSummaryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Every inbox of the host with its counts.

  MobileInboxSummaryProvider call(String hostId) =>
      MobileInboxSummaryProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileInboxSummaryProvider';
}

/// Every inbox of the host with its counts.

abstract class _$MobileInboxSummary
    extends $AsyncNotifier<List<InboxSummaryEntry>> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  FutureOr<List<InboxSummaryEntry>> build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<List<InboxSummaryEntry>>,
              List<InboxSummaryEntry>
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<List<InboxSummaryEntry>>,
                List<InboxSummaryEntry>
              >,
              AsyncValue<List<InboxSummaryEntry>>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Threads matching the filters, most recent activity first, one page at a
/// time. The runtime filters before it pages, so every page is full. A change
/// or new filters start again from the first page.

@ProviderFor(MobileInboxThreads)
final mobileInboxThreadsProvider = MobileInboxThreadsFamily._();

/// Threads matching the filters, most recent activity first, one page at a
/// time. The runtime filters before it pages, so every page is full. A change
/// or new filters start again from the first page.
final class MobileInboxThreadsProvider
    extends $AsyncNotifierProvider<MobileInboxThreads, InboxThreadPage> {
  /// Threads matching the filters, most recent activity first, one page at a
  /// time. The runtime filters before it pages, so every page is full. A change
  /// or new filters start again from the first page.
  MobileInboxThreadsProvider._({
    required MobileInboxThreadsFamily super.from,
    required (String, {String? inbox, InboxQuestionStatus? status})
    super.argument,
  }) : super(
         retry: null,
         name: r'mobileInboxThreadsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileInboxThreadsHash();

  @override
  String toString() {
    return r'mobileInboxThreadsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileInboxThreads create() => MobileInboxThreads();

  @override
  bool operator ==(Object other) {
    return other is MobileInboxThreadsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileInboxThreadsHash() =>
    r'b1a181971b26d48b0e877b3228b97bf5d55ba542';

/// Threads matching the filters, most recent activity first, one page at a
/// time. The runtime filters before it pages, so every page is full. A change
/// or new filters start again from the first page.

final class MobileInboxThreadsFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileInboxThreads,
          AsyncValue<InboxThreadPage>,
          InboxThreadPage,
          FutureOr<InboxThreadPage>,
          (String, {String? inbox, InboxQuestionStatus? status})
        > {
  MobileInboxThreadsFamily._()
    : super(
        retry: null,
        name: r'mobileInboxThreadsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Threads matching the filters, most recent activity first, one page at a
  /// time. The runtime filters before it pages, so every page is full. A change
  /// or new filters start again from the first page.

  MobileInboxThreadsProvider call(
    String hostId, {
    String? inbox,
    InboxQuestionStatus? status,
  }) => MobileInboxThreadsProvider._(
    argument: (hostId, inbox: inbox, status: status),
    from: this,
  );

  @override
  String toString() => r'mobileInboxThreadsProvider';
}

/// Threads matching the filters, most recent activity first, one page at a
/// time. The runtime filters before it pages, so every page is full. A change
/// or new filters start again from the first page.

abstract class _$MobileInboxThreads extends $AsyncNotifier<InboxThreadPage> {
  late final _$args =
      ref.$arg as (String, {String? inbox, InboxQuestionStatus? status});
  String get hostId => _$args.$1;
  String? get inbox => _$args.inbox;
  InboxQuestionStatus? get status => _$args.status;

  FutureOr<InboxThreadPage> build(
    String hostId, {
    String? inbox,
    InboxQuestionStatus? status,
  });
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AsyncValue<InboxThreadPage>, InboxThreadPage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<InboxThreadPage>, InboxThreadPage>,
              AsyncValue<InboxThreadPage>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, inbox: _$args.inbox, status: _$args.status),
    );
  }
}

/// One thread. Loading never acknowledges it: refreshes also run while the
/// app is in the background, and a read reply is read on every device.

@ProviderFor(MobileInboxThreadDetail)
final mobileInboxThreadDetailProvider = MobileInboxThreadDetailFamily._();

/// One thread. Loading never acknowledges it: refreshes also run while the
/// app is in the background, and a read reply is read on every device.
final class MobileInboxThreadDetailProvider
    extends $AsyncNotifierProvider<MobileInboxThreadDetail, InboxThreadDetail> {
  /// One thread. Loading never acknowledges it: refreshes also run while the
  /// app is in the background, and a read reply is read on every device.
  MobileInboxThreadDetailProvider._({
    required MobileInboxThreadDetailFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileInboxThreadDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileInboxThreadDetailHash();

  @override
  String toString() {
    return r'mobileInboxThreadDetailProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileInboxThreadDetail create() => MobileInboxThreadDetail();

  @override
  bool operator ==(Object other) {
    return other is MobileInboxThreadDetailProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileInboxThreadDetailHash() =>
    r'4315e9165a2f99be08e88de7276f90f8f3802ea6';

/// One thread. Loading never acknowledges it: refreshes also run while the
/// app is in the background, and a read reply is read on every device.

final class MobileInboxThreadDetailFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileInboxThreadDetail,
          AsyncValue<InboxThreadDetail>,
          InboxThreadDetail,
          FutureOr<InboxThreadDetail>,
          (String, String)
        > {
  MobileInboxThreadDetailFamily._()
    : super(
        retry: null,
        name: r'mobileInboxThreadDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One thread. Loading never acknowledges it: refreshes also run while the
  /// app is in the background, and a read reply is read on every device.

  MobileInboxThreadDetailProvider call(String hostId, String threadId) =>
      MobileInboxThreadDetailProvider._(
        argument: (hostId, threadId),
        from: this,
      );

  @override
  String toString() => r'mobileInboxThreadDetailProvider';
}

/// One thread. Loading never acknowledges it: refreshes also run while the
/// app is in the background, and a read reply is read on every device.

abstract class _$MobileInboxThreadDetail
    extends $AsyncNotifier<InboxThreadDetail> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get threadId => _$args.$2;

  FutureOr<InboxThreadDetail> build(String hostId, String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<InboxThreadDetail>, InboxThreadDetail>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<InboxThreadDetail>, InboxThreadDetail>,
              AsyncValue<InboxThreadDetail>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// Agents that can be asked, optionally only those of one workspace.

@ProviderFor(mobileInboxTargets)
final mobileInboxTargetsProvider = MobileInboxTargetsFamily._();

/// Agents that can be asked, optionally only those of one workspace.

final class MobileInboxTargetsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<InboxRecipient>>,
          List<InboxRecipient>,
          FutureOr<List<InboxRecipient>>
        >
    with
        $FutureModifier<List<InboxRecipient>>,
        $FutureProvider<List<InboxRecipient>> {
  /// Agents that can be asked, optionally only those of one workspace.
  MobileInboxTargetsProvider._({
    required MobileInboxTargetsFamily super.from,
    required (String, {String? workspaceId}) super.argument,
  }) : super(
         retry: null,
         name: r'mobileInboxTargetsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileInboxTargetsHash();

  @override
  String toString() {
    return r'mobileInboxTargetsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<InboxRecipient>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<InboxRecipient>> create(Ref ref) {
    final argument = this.argument as (String, {String? workspaceId});
    return mobileInboxTargets(
      ref,
      argument.$1,
      workspaceId: argument.workspaceId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileInboxTargetsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileInboxTargetsHash() =>
    r'96f41a9aa69db1f7cb760c862c4cf4fa9d479ac5';

/// Agents that can be asked, optionally only those of one workspace.

final class MobileInboxTargetsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<InboxRecipient>>,
          (String, {String? workspaceId})
        > {
  MobileInboxTargetsFamily._()
    : super(
        retry: null,
        name: r'mobileInboxTargetsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Agents that can be asked, optionally only those of one workspace.

  MobileInboxTargetsProvider call(String hostId, {String? workspaceId}) =>
      MobileInboxTargetsProvider._(
        argument: (hostId, workspaceId: workspaceId),
        from: this,
      );

  @override
  String toString() => r'mobileInboxTargetsProvider';
}

/// Names of the host's workspaces, to group the agents that can be asked.

@ProviderFor(mobileInboxWorkspaceNames)
final mobileInboxWorkspaceNamesProvider = MobileInboxWorkspaceNamesFamily._();

/// Names of the host's workspaces, to group the agents that can be asked.

final class MobileInboxWorkspaceNamesProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, String>>,
          Map<String, String>,
          FutureOr<Map<String, String>>
        >
    with
        $FutureModifier<Map<String, String>>,
        $FutureProvider<Map<String, String>> {
  /// Names of the host's workspaces, to group the agents that can be asked.
  MobileInboxWorkspaceNamesProvider._({
    required MobileInboxWorkspaceNamesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileInboxWorkspaceNamesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileInboxWorkspaceNamesHash();

  @override
  String toString() {
    return r'mobileInboxWorkspaceNamesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Map<String, String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, String>> create(Ref ref) {
    final argument = this.argument as String;
    return mobileInboxWorkspaceNames(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileInboxWorkspaceNamesProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileInboxWorkspaceNamesHash() =>
    r'10252b9f1c870f18876bb7f4b64b5817eea73e5c';

/// Names of the host's workspaces, to group the agents that can be asked.

final class MobileInboxWorkspaceNamesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Map<String, String>>, String> {
  MobileInboxWorkspaceNamesFamily._()
    : super(
        retry: null,
        name: r'mobileInboxWorkspaceNamesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Names of the host's workspaces, to group the agents that can be asked.

  MobileInboxWorkspaceNamesProvider call(String hostId) =>
      MobileInboxWorkspaceNamesProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileInboxWorkspaceNamesProvider';
}

/// Inbox and status filters of the list, kept per host while the app runs.

@ProviderFor(MobileInboxListController)
final mobileInboxListControllerProvider = MobileInboxListControllerFamily._();

/// Inbox and status filters of the list, kept per host while the app runs.
final class MobileInboxListControllerProvider
    extends $NotifierProvider<MobileInboxListController, MobileInboxListState> {
  /// Inbox and status filters of the list, kept per host while the app runs.
  MobileInboxListControllerProvider._({
    required MobileInboxListControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileInboxListControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileInboxListControllerHash();

  @override
  String toString() {
    return r'mobileInboxListControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileInboxListController create() => MobileInboxListController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MobileInboxListState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MobileInboxListState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileInboxListControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileInboxListControllerHash() =>
    r'5d59d0cbc045ffc9e69a546963eaf4ecf7b9efad';

/// Inbox and status filters of the list, kept per host while the app runs.

final class MobileInboxListControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileInboxListController,
          MobileInboxListState,
          MobileInboxListState,
          MobileInboxListState,
          String
        > {
  MobileInboxListControllerFamily._()
    : super(
        retry: null,
        name: r'mobileInboxListControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Inbox and status filters of the list, kept per host while the app runs.

  MobileInboxListControllerProvider call(String hostId) =>
      MobileInboxListControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileInboxListControllerProvider';
}

/// Inbox and status filters of the list, kept per host while the app runs.

abstract class _$MobileInboxListController
    extends $Notifier<MobileInboxListState> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  MobileInboxListState build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<MobileInboxListState, MobileInboxListState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MobileInboxListState, MobileInboxListState>,
              MobileInboxListState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Conversations between agents, optionally of one workspace. Reloads when
/// the runtime announces a change.

@ProviderFor(MobileAgentConversations)
final mobileAgentConversationsProvider = MobileAgentConversationsFamily._();

/// Conversations between agents, optionally of one workspace. Reloads when
/// the runtime announces a change.
final class MobileAgentConversationsProvider
    extends
        $AsyncNotifierProvider<
          MobileAgentConversations,
          AgentConversationPage
        > {
  /// Conversations between agents, optionally of one workspace. Reloads when
  /// the runtime announces a change.
  MobileAgentConversationsProvider._({
    required MobileAgentConversationsFamily super.from,
    required (String, {String? workspaceId}) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAgentConversationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAgentConversationsHash();

  @override
  String toString() {
    return r'mobileAgentConversationsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileAgentConversations create() => MobileAgentConversations();

  @override
  bool operator ==(Object other) {
    return other is MobileAgentConversationsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAgentConversationsHash() =>
    r'e0ca91b21c612ace6551579029173d50aa5a4f89';

/// Conversations between agents, optionally of one workspace. Reloads when
/// the runtime announces a change.

final class MobileAgentConversationsFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAgentConversations,
          AsyncValue<AgentConversationPage>,
          AgentConversationPage,
          FutureOr<AgentConversationPage>,
          (String, {String? workspaceId})
        > {
  MobileAgentConversationsFamily._()
    : super(
        retry: null,
        name: r'mobileAgentConversationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Conversations between agents, optionally of one workspace. Reloads when
  /// the runtime announces a change.

  MobileAgentConversationsProvider call(String hostId, {String? workspaceId}) =>
      MobileAgentConversationsProvider._(
        argument: (hostId, workspaceId: workspaceId),
        from: this,
      );

  @override
  String toString() => r'mobileAgentConversationsProvider';
}

/// Conversations between agents, optionally of one workspace. Reloads when
/// the runtime announces a change.

abstract class _$MobileAgentConversations
    extends $AsyncNotifier<AgentConversationPage> {
  late final _$args = ref.$arg as (String, {String? workspaceId});
  String get hostId => _$args.$1;
  String? get workspaceId => _$args.workspaceId;

  FutureOr<AgentConversationPage> build(String hostId, {String? workspaceId});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<AgentConversationPage>, AgentConversationPage>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AgentConversationPage>,
                AgentConversationPage
              >,
              AsyncValue<AgentConversationPage>,
              Object?,
              Object?
            >;
    return element.handleCreate(
      ref,
      () => build(_$args.$1, workspaceId: _$args.workspaceId),
    );
  }
}

@ProviderFor(MobileAgentConversationDetail)
final mobileAgentConversationDetailProvider =
    MobileAgentConversationDetailFamily._();

final class MobileAgentConversationDetailProvider
    extends
        $AsyncNotifierProvider<
          MobileAgentConversationDetail,
          AgentConversationDetail
        > {
  MobileAgentConversationDetailProvider._({
    required MobileAgentConversationDetailFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileAgentConversationDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAgentConversationDetailHash();

  @override
  String toString() {
    return r'mobileAgentConversationDetailProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  MobileAgentConversationDetail create() => MobileAgentConversationDetail();

  @override
  bool operator ==(Object other) {
    return other is MobileAgentConversationDetailProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAgentConversationDetailHash() =>
    r'927fc0406bbda7bd52fa5f7640f7cdfdbc770ff5';

final class MobileAgentConversationDetailFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAgentConversationDetail,
          AsyncValue<AgentConversationDetail>,
          AgentConversationDetail,
          FutureOr<AgentConversationDetail>,
          (String, String)
        > {
  MobileAgentConversationDetailFamily._()
    : super(
        retry: null,
        name: r'mobileAgentConversationDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileAgentConversationDetailProvider call(String hostId, String threadId) =>
      MobileAgentConversationDetailProvider._(
        argument: (hostId, threadId),
        from: this,
      );

  @override
  String toString() => r'mobileAgentConversationDetailProvider';
}

abstract class _$MobileAgentConversationDetail
    extends $AsyncNotifier<AgentConversationDetail> {
  late final _$args = ref.$arg as (String, String);
  String get hostId => _$args.$1;
  String get threadId => _$args.$2;

  FutureOr<AgentConversationDetail> build(String hostId, String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AgentConversationDetail>,
              AgentConversationDetail
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AgentConversationDetail>,
                AgentConversationDetail
              >,
              AsyncValue<AgentConversationDetail>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}

/// Agent and tab title of each running terminal, so conversations show names
/// instead of handles where the runtime knows them.

@ProviderFor(mobileInboxHandleLabels)
final mobileInboxHandleLabelsProvider = MobileInboxHandleLabelsFamily._();

/// Agent and tab title of each running terminal, so conversations show names
/// instead of handles where the runtime knows them.

final class MobileInboxHandleLabelsProvider
    extends
        $FunctionalProvider<
          AsyncValue<Map<String, String>>,
          Map<String, String>,
          FutureOr<Map<String, String>>
        >
    with
        $FutureModifier<Map<String, String>>,
        $FutureProvider<Map<String, String>> {
  /// Agent and tab title of each running terminal, so conversations show names
  /// instead of handles where the runtime knows them.
  MobileInboxHandleLabelsProvider._({
    required MobileInboxHandleLabelsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileInboxHandleLabelsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileInboxHandleLabelsHash();

  @override
  String toString() {
    return r'mobileInboxHandleLabelsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Map<String, String>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Map<String, String>> create(Ref ref) {
    final argument = this.argument as String;
    return mobileInboxHandleLabels(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileInboxHandleLabelsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileInboxHandleLabelsHash() =>
    r'72386f6baf35034805fa64f334330b8e68acd60c';

/// Agent and tab title of each running terminal, so conversations show names
/// instead of handles where the runtime knows them.

final class MobileInboxHandleLabelsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Map<String, String>>, String> {
  MobileInboxHandleLabelsFamily._()
    : super(
        retry: null,
        name: r'mobileInboxHandleLabelsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Agent and tab title of each running terminal, so conversations show names
  /// instead of handles where the runtime knows them.

  MobileInboxHandleLabelsProvider call(String hostId) =>
      MobileInboxHandleLabelsProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileInboxHandleLabelsProvider';
}

/// Workspace filter of the agent conversations list, kept per host.

@ProviderFor(MobileAgentConversationWorkspace)
final mobileAgentConversationWorkspaceProvider =
    MobileAgentConversationWorkspaceFamily._();

/// Workspace filter of the agent conversations list, kept per host.
final class MobileAgentConversationWorkspaceProvider
    extends $NotifierProvider<MobileAgentConversationWorkspace, String?> {
  /// Workspace filter of the agent conversations list, kept per host.
  MobileAgentConversationWorkspaceProvider._({
    required MobileAgentConversationWorkspaceFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileAgentConversationWorkspaceProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileAgentConversationWorkspaceHash();

  @override
  String toString() {
    return r'mobileAgentConversationWorkspaceProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileAgentConversationWorkspace create() =>
      MobileAgentConversationWorkspace();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileAgentConversationWorkspaceProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileAgentConversationWorkspaceHash() =>
    r'7b7040159c4345d9fcd616339dd7ac8b0695f440';

/// Workspace filter of the agent conversations list, kept per host.

final class MobileAgentConversationWorkspaceFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileAgentConversationWorkspace,
          String?,
          String?,
          String?,
          String
        > {
  MobileAgentConversationWorkspaceFamily._()
    : super(
        retry: null,
        name: r'mobileAgentConversationWorkspaceProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Workspace filter of the agent conversations list, kept per host.

  MobileAgentConversationWorkspaceProvider call(String hostId) =>
      MobileAgentConversationWorkspaceProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileAgentConversationWorkspaceProvider';
}

/// Workspace filter of the agent conversations list, kept per host.

abstract class _$MobileAgentConversationWorkspace extends $Notifier<String?> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  String? build(String hostId);
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
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// Which half of the inbox is open, kept per host while the app runs.

@ProviderFor(MobileInboxSectionController)
final mobileInboxSectionControllerProvider =
    MobileInboxSectionControllerFamily._();

/// Which half of the inbox is open, kept per host while the app runs.
final class MobileInboxSectionControllerProvider
    extends $NotifierProvider<MobileInboxSectionController, InboxSection> {
  /// Which half of the inbox is open, kept per host while the app runs.
  MobileInboxSectionControllerProvider._({
    required MobileInboxSectionControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileInboxSectionControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileInboxSectionControllerHash();

  @override
  String toString() {
    return r'mobileInboxSectionControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileInboxSectionController create() => MobileInboxSectionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(InboxSection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<InboxSection>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileInboxSectionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileInboxSectionControllerHash() =>
    r'f22519d216a8f91bb0daa07506b070b1071f3aaa';

/// Which half of the inbox is open, kept per host while the app runs.

final class MobileInboxSectionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileInboxSectionController,
          InboxSection,
          InboxSection,
          InboxSection,
          String
        > {
  MobileInboxSectionControllerFamily._()
    : super(
        retry: null,
        name: r'mobileInboxSectionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Which half of the inbox is open, kept per host while the app runs.

  MobileInboxSectionControllerProvider call(String hostId) =>
      MobileInboxSectionControllerProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileInboxSectionControllerProvider';
}

/// Which half of the inbox is open, kept per host while the app runs.

abstract class _$MobileInboxSectionController extends $Notifier<InboxSection> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  InboxSection build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<InboxSection, InboxSection>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<InboxSection, InboxSection>,
              InboxSection,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
