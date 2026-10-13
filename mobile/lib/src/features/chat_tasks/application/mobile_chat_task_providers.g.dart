// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mobile_chat_task_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Chat orchestration over the paired runtime: the same connection the
/// workspace and chat screens use, so it rebuilds with every reconnect.

@ProviderFor(mobileChatTaskRepository)
final mobileChatTaskRepositoryProvider = MobileChatTaskRepositoryFamily._();

/// Chat orchestration over the paired runtime: the same connection the
/// workspace and chat screens use, so it rebuilds with every reconnect.

final class MobileChatTaskRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatOrchestrationRepository>,
          AgentChatOrchestrationRepository,
          FutureOr<AgentChatOrchestrationRepository>
        >
    with
        $FutureModifier<AgentChatOrchestrationRepository>,
        $FutureProvider<AgentChatOrchestrationRepository> {
  /// Chat orchestration over the paired runtime: the same connection the
  /// workspace and chat screens use, so it rebuilds with every reconnect.
  MobileChatTaskRepositoryProvider._({
    required MobileChatTaskRepositoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskRepositoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskRepositoryHash();

  @override
  String toString() {
    return r'mobileChatTaskRepositoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatOrchestrationRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatOrchestrationRepository> create(Ref ref) {
    final argument = this.argument as String;
    return mobileChatTaskRepository(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskRepositoryProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskRepositoryHash() =>
    r'412ea9d350f670e9a0cd2c58abfec3d3ef6cc4a4';

/// Chat orchestration over the paired runtime: the same connection the
/// workspace and chat screens use, so it rebuilds with every reconnect.

final class MobileChatTaskRepositoryFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatOrchestrationRepository>,
          String
        > {
  MobileChatTaskRepositoryFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskRepositoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Chat orchestration over the paired runtime: the same connection the
  /// workspace and chat screens use, so it rebuilds with every reconnect.

  MobileChatTaskRepositoryProvider call(String hostId) =>
      MobileChatTaskRepositoryProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileChatTaskRepositoryProvider';
}

/// Whether the paired runtime runs chat tasks. An older runtime, a client
/// without chats or an unreachable host is a plain no, never an error.

@ProviderFor(mobileChatTasksSupported)
final mobileChatTasksSupportedProvider = MobileChatTasksSupportedFamily._();

/// Whether the paired runtime runs chat tasks. An older runtime, a client
/// without chats or an unreachable host is a plain no, never an error.

final class MobileChatTasksSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the paired runtime runs chat tasks. An older runtime, a client
  /// without chats or an unreachable host is a plain no, never an error.
  MobileChatTasksSupportedProvider._({
    required MobileChatTasksSupportedFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTasksSupportedProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTasksSupportedHash();

  @override
  String toString() {
    return r'mobileChatTasksSupportedProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    final argument = this.argument as String;
    return mobileChatTasksSupported(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTasksSupportedProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTasksSupportedHash() =>
    r'27906480e36d1fda22b8b4429a9987cef495b614';

/// Whether the paired runtime runs chat tasks. An older runtime, a client
/// without chats or an unreachable host is a plain no, never an error.

final class MobileChatTasksSupportedFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<bool>, String> {
  MobileChatTasksSupportedFamily._()
    : super(
        retry: null,
        name: r'mobileChatTasksSupportedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Whether the paired runtime runs chat tasks. An older runtime, a client
  /// without chats or an unreachable host is a plain no, never an error.

  MobileChatTasksSupportedProvider call(String hostId) =>
      MobileChatTasksSupportedProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileChatTasksSupportedProvider';
}

/// Allocates request ids; tests pin it.

@ProviderFor(mobileChatTaskIdGenerator)
final mobileChatTaskIdGeneratorProvider = MobileChatTaskIdGeneratorProvider._();

/// Allocates request ids; tests pin it.

final class MobileChatTaskIdGeneratorProvider
    extends
        $FunctionalProvider<
          String Function(),
          String Function(),
          String Function()
        >
    with $Provider<String Function()> {
  /// Allocates request ids; tests pin it.
  MobileChatTaskIdGeneratorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mobileChatTaskIdGeneratorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskIdGeneratorHash();

  @$internal
  @override
  $ProviderElement<String Function()> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  String Function() create(Ref ref) {
    return mobileChatTaskIdGenerator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String Function() value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String Function()>(value),
    );
  }
}

String _$mobileChatTaskIdGeneratorHash() =>
    r'8a0fb4fc7176af999e51ac81b60d76287bab9142';

@ProviderFor(mobileChatTaskActions)
final mobileChatTaskActionsProvider = MobileChatTaskActionsFamily._();

final class MobileChatTaskActionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatTaskActions>,
          AgentChatTaskActions,
          FutureOr<AgentChatTaskActions>
        >
    with
        $FutureModifier<AgentChatTaskActions>,
        $FutureProvider<AgentChatTaskActions> {
  MobileChatTaskActionsProvider._({
    required MobileChatTaskActionsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskActionsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskActionsHash();

  @override
  String toString() {
    return r'mobileChatTaskActionsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatTaskActions> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatTaskActions> create(Ref ref) {
    final argument = this.argument as String;
    return mobileChatTaskActions(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskActionsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskActionsHash() =>
    r'180c2702c58378c85df0aaf969734cd81bbefc3e';

final class MobileChatTaskActionsFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AgentChatTaskActions>, String> {
  MobileChatTaskActionsFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskActionsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileChatTaskActionsProvider call(String hostId) =>
      MobileChatTaskActionsProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileChatTaskActionsProvider';
}

/// One list, read again on every change that may touch it.

@ProviderFor(mobileChatTaskList)
final mobileChatTaskListProvider = MobileChatTaskListFamily._();

/// One list, read again on every change that may touch it.

final class MobileChatTaskListProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatTaskPage>,
          AgentChatTaskPage,
          Stream<AgentChatTaskPage>
        >
    with
        $FutureModifier<AgentChatTaskPage>,
        $StreamProvider<AgentChatTaskPage> {
  /// One list, read again on every change that may touch it.
  MobileChatTaskListProvider._({
    required MobileChatTaskListFamily super.from,
    required (String, AgentChatTaskQuery) super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskListProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskListHash();

  @override
  String toString() {
    return r'mobileChatTaskListProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<AgentChatTaskPage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<AgentChatTaskPage> create(Ref ref) {
    final argument = this.argument as (String, AgentChatTaskQuery);
    return mobileChatTaskList(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskListProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskListHash() =>
    r'fe5e72efd33c07828e2b3deb7518525ad09e5cf2';

/// One list, read again on every change that may touch it.

final class MobileChatTaskListFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<AgentChatTaskPage>,
          (String, AgentChatTaskQuery)
        > {
  MobileChatTaskListFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskListProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One list, read again on every change that may touch it.

  MobileChatTaskListProvider call(String hostId, AgentChatTaskQuery query) =>
      MobileChatTaskListProvider._(argument: (hostId, query), from: this);

  @override
  String toString() => r'mobileChatTaskListProvider';
}

/// Tasks waiting for input, or failed and not reviewed.

@ProviderFor(mobileChatTaskAttentionCount)
final mobileChatTaskAttentionCountProvider =
    MobileChatTaskAttentionCountFamily._();

/// Tasks waiting for input, or failed and not reviewed.

final class MobileChatTaskAttentionCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Tasks waiting for input, or failed and not reviewed.
  MobileChatTaskAttentionCountProvider._({
    required MobileChatTaskAttentionCountFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskAttentionCountProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskAttentionCountHash();

  @override
  String toString() {
    return r'mobileChatTaskAttentionCountProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    final argument = this.argument as String;
    return mobileChatTaskAttentionCount(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskAttentionCountProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskAttentionCountHash() =>
    r'70c594a491f3ac32ace3e7bf0dd15a9f19a59702';

/// Tasks waiting for input, or failed and not reviewed.

final class MobileChatTaskAttentionCountFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<int>, String> {
  MobileChatTaskAttentionCountFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskAttentionCountProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Tasks waiting for input, or failed and not reviewed.

  MobileChatTaskAttentionCountProvider call(String hostId) =>
      MobileChatTaskAttentionCountProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileChatTaskAttentionCountProvider';
}

/// One task, live. Reading it never acknowledges its result.

@ProviderFor(mobileChatTaskDetail)
final mobileChatTaskDetailProvider = MobileChatTaskDetailFamily._();

/// One task, live. Reading it never acknowledges its result.

final class MobileChatTaskDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatTask>,
          AgentChatTask,
          Stream<AgentChatTask>
        >
    with $FutureModifier<AgentChatTask>, $StreamProvider<AgentChatTask> {
  /// One task, live. Reading it never acknowledges its result.
  MobileChatTaskDetailProvider._({
    required MobileChatTaskDetailFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskDetailHash();

  @override
  String toString() {
    return r'mobileChatTaskDetailProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<AgentChatTask> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<AgentChatTask> create(Ref ref) {
    final argument = this.argument as (String, String);
    return mobileChatTaskDetail(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskDetailHash() =>
    r'4239f0e55a9273c79644aef70a6a81ac5ffbd18f';

/// One task, live. Reading it never acknowledges its result.

final class MobileChatTaskDetailFamily extends $Family
    with $FunctionalFamilyOverride<Stream<AgentChatTask>, (String, String)> {
  MobileChatTaskDetailFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One task, live. Reading it never acknowledges its result.

  MobileChatTaskDetailProvider call(String hostId, String taskId) =>
      MobileChatTaskDetailProvider._(argument: (hostId, taskId), from: this);

  @override
  String toString() => r'mobileChatTaskDetailProvider';
}

@ProviderFor(mobileChatTaskRequests)
final mobileChatTaskRequestsProvider = MobileChatTaskRequestsFamily._();

final class MobileChatTaskRequestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentChatTaskRequest>>,
          List<AgentChatTaskRequest>,
          FutureOr<List<AgentChatTaskRequest>>
        >
    with
        $FutureModifier<List<AgentChatTaskRequest>>,
        $FutureProvider<List<AgentChatTaskRequest>> {
  MobileChatTaskRequestsProvider._({
    required MobileChatTaskRequestsFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskRequestsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskRequestsHash();

  @override
  String toString() {
    return r'mobileChatTaskRequestsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<List<AgentChatTaskRequest>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentChatTaskRequest>> create(Ref ref) {
    final argument = this.argument as (String, String);
    return mobileChatTaskRequests(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskRequestsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskRequestsHash() =>
    r'59dce56c86fca4cd48f16caeeeb905be6daf943d';

final class MobileChatTaskRequestsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<AgentChatTaskRequest>>,
          (String, String)
        > {
  MobileChatTaskRequestsFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskRequestsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileChatTaskRequestsProvider call(String hostId, String taskId) =>
      MobileChatTaskRequestsProvider._(argument: (hostId, taskId), from: this);

  @override
  String toString() => r'mobileChatTaskRequestsProvider';
}

/// The agents a delegation can start: the workspace's own host catalog when
/// the workspace exists, else the runtime's, with its orchestration flags.

@ProviderFor(mobileChatTaskAgentCatalog)
final mobileChatTaskAgentCatalogProvider = MobileChatTaskAgentCatalogFamily._();

/// The agents a delegation can start: the workspace's own host catalog when
/// the workspace exists, else the runtime's, with its orchestration flags.

final class MobileChatTaskAgentCatalogProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatOrchestrationCapabilities>,
          AgentChatOrchestrationCapabilities,
          FutureOr<AgentChatOrchestrationCapabilities>
        >
    with
        $FutureModifier<AgentChatOrchestrationCapabilities>,
        $FutureProvider<AgentChatOrchestrationCapabilities> {
  /// The agents a delegation can start: the workspace's own host catalog when
  /// the workspace exists, else the runtime's, with its orchestration flags.
  MobileChatTaskAgentCatalogProvider._({
    required MobileChatTaskAgentCatalogFamily super.from,
    required (String, String?) super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskAgentCatalogProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskAgentCatalogHash();

  @override
  String toString() {
    return r'mobileChatTaskAgentCatalogProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatOrchestrationCapabilities> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatOrchestrationCapabilities> create(Ref ref) {
    final argument = this.argument as (String, String?);
    return mobileChatTaskAgentCatalog(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskAgentCatalogProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskAgentCatalogHash() =>
    r'5a8aadc68fb116e9379b2ae94315d580fb8b0fd1';

/// The agents a delegation can start: the workspace's own host catalog when
/// the workspace exists, else the runtime's, with its orchestration flags.

final class MobileChatTaskAgentCatalogFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatOrchestrationCapabilities>,
          (String, String?)
        > {
  MobileChatTaskAgentCatalogFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskAgentCatalogProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The agents a delegation can start: the workspace's own host catalog when
  /// the workspace exists, else the runtime's, with its orchestration flags.

  MobileChatTaskAgentCatalogProvider call(String hostId, String? workspaceId) =>
      MobileChatTaskAgentCatalogProvider._(
        argument: (hostId, workspaceId),
        from: this,
      );

  @override
  String toString() => r'mobileChatTaskAgentCatalogProvider';
}

/// Chats across every project and host, for the Existing Chat target.

@ProviderFor(mobileChatTaskDirectory)
final mobileChatTaskDirectoryProvider = MobileChatTaskDirectoryFamily._();

/// Chats across every project and host, for the Existing Chat target.

final class MobileChatTaskDirectoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentChatDirectoryEntry>>,
          List<AgentChatDirectoryEntry>,
          FutureOr<List<AgentChatDirectoryEntry>>
        >
    with
        $FutureModifier<List<AgentChatDirectoryEntry>>,
        $FutureProvider<List<AgentChatDirectoryEntry>> {
  /// Chats across every project and host, for the Existing Chat target.
  MobileChatTaskDirectoryProvider._({
    required MobileChatTaskDirectoryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskDirectoryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskDirectoryHash();

  @override
  String toString() {
    return r'mobileChatTaskDirectoryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<AgentChatDirectoryEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentChatDirectoryEntry>> create(Ref ref) {
    final argument = this.argument as String;
    return mobileChatTaskDirectory(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskDirectoryProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskDirectoryHash() =>
    r'054578144b8fb05bf24869489b97c09f56180d53';

/// Chats across every project and host, for the Existing Chat target.

final class MobileChatTaskDirectoryFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<AgentChatDirectoryEntry>>,
          String
        > {
  MobileChatTaskDirectoryFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskDirectoryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Chats across every project and host, for the Existing Chat target.

  MobileChatTaskDirectoryProvider call(String hostId) =>
      MobileChatTaskDirectoryProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileChatTaskDirectoryProvider';
}

/// A chat's title and place, for the sender of a chat message.

@ProviderFor(mobileChatTaskChat)
final mobileChatTaskChatProvider = MobileChatTaskChatFamily._();

/// A chat's title and place, for the sender of a chat message.

final class MobileChatTaskChatProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatDirectoryEntry>,
          AgentChatDirectoryEntry,
          FutureOr<AgentChatDirectoryEntry>
        >
    with
        $FutureModifier<AgentChatDirectoryEntry>,
        $FutureProvider<AgentChatDirectoryEntry> {
  /// A chat's title and place, for the sender of a chat message.
  MobileChatTaskChatProvider._({
    required MobileChatTaskChatFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskChatProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskChatHash();

  @override
  String toString() {
    return r'mobileChatTaskChatProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatDirectoryEntry> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatDirectoryEntry> create(Ref ref) {
    final argument = this.argument as (String, String);
    return mobileChatTaskChat(ref, argument.$1, argument.$2);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskChatProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskChatHash() =>
    r'90755b21ba18d4a222b99550db53a8452f6dadcf';

/// A chat's title and place, for the sender of a chat message.

final class MobileChatTaskChatFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatDirectoryEntry>,
          (String, String)
        > {
  MobileChatTaskChatFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskChatProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A chat's title and place, for the sender of a chat message.

  MobileChatTaskChatProvider call(String hostId, String chatId) =>
      MobileChatTaskChatProvider._(argument: (hostId, chatId), from: this);

  @override
  String toString() => r'mobileChatTaskChatProvider';
}

@ProviderFor(mobileChatTaskPlaces)
final mobileChatTaskPlacesProvider = MobileChatTaskPlacesFamily._();

final class MobileChatTaskPlacesProvider
    extends
        $FunctionalProvider<
          AsyncValue<MobileChatTaskPlaces>,
          MobileChatTaskPlaces,
          FutureOr<MobileChatTaskPlaces>
        >
    with
        $FutureModifier<MobileChatTaskPlaces>,
        $FutureProvider<MobileChatTaskPlaces> {
  MobileChatTaskPlacesProvider._({
    required MobileChatTaskPlacesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskPlacesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskPlacesHash();

  @override
  String toString() {
    return r'mobileChatTaskPlacesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<MobileChatTaskPlaces> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<MobileChatTaskPlaces> create(Ref ref) {
    final argument = this.argument as String;
    return mobileChatTaskPlaces(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskPlacesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskPlacesHash() =>
    r'995333a93d9651294cefc16f3c6e6e4a39ff5da6';

final class MobileChatTaskPlacesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<MobileChatTaskPlaces>, String> {
  MobileChatTaskPlacesFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskPlacesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MobileChatTaskPlacesProvider call(String hostId) =>
      MobileChatTaskPlacesProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileChatTaskPlacesProvider';
}

/// The group Chat Tasks shows on this host, kept while the app runs.

@ProviderFor(MobileChatTaskFilter)
final mobileChatTaskFilterProvider = MobileChatTaskFilterFamily._();

/// The group Chat Tasks shows on this host, kept while the app runs.
final class MobileChatTaskFilterProvider
    extends $NotifierProvider<MobileChatTaskFilter, AgentChatTaskBucket?> {
  /// The group Chat Tasks shows on this host, kept while the app runs.
  MobileChatTaskFilterProvider._({
    required MobileChatTaskFilterFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileChatTaskFilterProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileChatTaskFilterHash();

  @override
  String toString() {
    return r'mobileChatTaskFilterProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileChatTaskFilter create() => MobileChatTaskFilter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatTaskBucket? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatTaskBucket?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileChatTaskFilterProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileChatTaskFilterHash() =>
    r'6e37199cef0fa341e91c62b8b2c1df1d6f02345b';

/// The group Chat Tasks shows on this host, kept while the app runs.

final class MobileChatTaskFilterFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileChatTaskFilter,
          AgentChatTaskBucket?,
          AgentChatTaskBucket?,
          AgentChatTaskBucket?,
          String
        > {
  MobileChatTaskFilterFamily._()
    : super(
        retry: null,
        name: r'mobileChatTaskFilterProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The group Chat Tasks shows on this host, kept while the app runs.

  MobileChatTaskFilterProvider call(String hostId) =>
      MobileChatTaskFilterProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileChatTaskFilterProvider';
}

/// The group Chat Tasks shows on this host, kept while the app runs.

abstract class _$MobileChatTaskFilter extends $Notifier<AgentChatTaskBucket?> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  AgentChatTaskBucket? build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AgentChatTaskBucket?, AgentChatTaskBucket?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AgentChatTaskBucket?, AgentChatTaskBucket?>,
              AgentChatTaskBucket?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The Delegate Task form of one host.

@ProviderFor(MobileDelegateChatTaskForm)
final mobileDelegateChatTaskFormProvider = MobileDelegateChatTaskFormFamily._();

/// The Delegate Task form of one host.
final class MobileDelegateChatTaskFormProvider
    extends
        $NotifierProvider<MobileDelegateChatTaskForm, AgentChatDelegateDraft> {
  /// The Delegate Task form of one host.
  MobileDelegateChatTaskFormProvider._({
    required MobileDelegateChatTaskFormFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mobileDelegateChatTaskFormProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mobileDelegateChatTaskFormHash();

  @override
  String toString() {
    return r'mobileDelegateChatTaskFormProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MobileDelegateChatTaskForm create() => MobileDelegateChatTaskForm();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatDelegateDraft value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatDelegateDraft>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MobileDelegateChatTaskFormProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mobileDelegateChatTaskFormHash() =>
    r'ba42d4b8fbbeba8abd26e6ecf462bb3cfabd1d39';

/// The Delegate Task form of one host.

final class MobileDelegateChatTaskFormFamily extends $Family
    with
        $ClassFamilyOverride<
          MobileDelegateChatTaskForm,
          AgentChatDelegateDraft,
          AgentChatDelegateDraft,
          AgentChatDelegateDraft,
          String
        > {
  MobileDelegateChatTaskFormFamily._()
    : super(
        retry: null,
        name: r'mobileDelegateChatTaskFormProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The Delegate Task form of one host.

  MobileDelegateChatTaskFormProvider call(String hostId) =>
      MobileDelegateChatTaskFormProvider._(argument: hostId, from: this);

  @override
  String toString() => r'mobileDelegateChatTaskFormProvider';
}

/// The Delegate Task form of one host.

abstract class _$MobileDelegateChatTaskForm
    extends $Notifier<AgentChatDelegateDraft> {
  late final _$args = ref.$arg as String;
  String get hostId => _$args;

  AgentChatDelegateDraft build(String hostId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AgentChatDelegateDraft, AgentChatDelegateDraft>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AgentChatDelegateDraft, AgentChatDelegateDraft>,
              AgentChatDelegateDraft,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
