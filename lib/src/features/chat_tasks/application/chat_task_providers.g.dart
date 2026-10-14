// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_task_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(chatTaskRepository)
final chatTaskRepositoryProvider = ChatTaskRepositoryProvider._();

final class ChatTaskRepositoryProvider
    extends
        $FunctionalProvider<
          AgentChatOrchestrationRepository,
          AgentChatOrchestrationRepository,
          AgentChatOrchestrationRepository
        >
    with $Provider<AgentChatOrchestrationRepository> {
  ChatTaskRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatTaskRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatTaskRepositoryHash();

  @$internal
  @override
  $ProviderElement<AgentChatOrchestrationRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AgentChatOrchestrationRepository create(Ref ref) {
    return chatTaskRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgentChatOrchestrationRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgentChatOrchestrationRepository>(
        value,
      ),
    );
  }
}

String _$chatTaskRepositoryHash() =>
    r'5506da72be77683e6b21624b0f2976ba42c2e929';

/// Whether the connected runtime runs chat tasks. An unreachable runtime
/// reads as unsupported, so no entry point is offered that would fail.

@ProviderFor(chatTasksSupported)
final chatTasksSupportedProvider = ChatTasksSupportedProvider._();

/// Whether the connected runtime runs chat tasks. An unreachable runtime
/// reads as unsupported, so no entry point is offered that would fail.

final class ChatTasksSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether the connected runtime runs chat tasks. An unreachable runtime
  /// reads as unsupported, so no entry point is offered that would fail.
  ChatTasksSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatTasksSupportedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatTasksSupportedHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return chatTasksSupported(ref);
  }
}

String _$chatTasksSupportedHash() =>
    r'c2a68adada9e7633587838f8a62bdd8ccf80ac27';

/// One Activity list, read again on every change that may touch it. Hidden
/// windows do no reads.

@ProviderFor(chatTaskList)
final chatTaskListProvider = ChatTaskListFamily._();

/// One Activity list, read again on every change that may touch it. Hidden
/// windows do no reads.

final class ChatTaskListProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatTaskPage>,
          AgentChatTaskPage,
          Stream<AgentChatTaskPage>
        >
    with
        $FutureModifier<AgentChatTaskPage>,
        $StreamProvider<AgentChatTaskPage> {
  /// One Activity list, read again on every change that may touch it. Hidden
  /// windows do no reads.
  ChatTaskListProvider._({
    required ChatTaskListFamily super.from,
    required AgentChatTaskQuery super.argument,
  }) : super(
         retry: chatTaskNoRetry,
         name: r'chatTaskListProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatTaskListHash();

  @override
  String toString() {
    return r'chatTaskListProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<AgentChatTaskPage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<AgentChatTaskPage> create(Ref ref) {
    final argument = this.argument as AgentChatTaskQuery;
    return chatTaskList(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatTaskListProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatTaskListHash() => r'24f0d050d821ce05e808565ff14af60d0ea58ea3';

/// One Activity list, read again on every change that may touch it. Hidden
/// windows do no reads.

final class ChatTaskListFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<AgentChatTaskPage>,
          AgentChatTaskQuery
        > {
  ChatTaskListFamily._()
    : super(
        retry: chatTaskNoRetry,
        name: r'chatTaskListProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One Activity list, read again on every change that may touch it. Hidden
  /// windows do no reads.

  ChatTaskListProvider call(AgentChatTaskQuery query) =>
      ChatTaskListProvider._(argument: query, from: this);

  @override
  String toString() => r'chatTaskListProvider';
}

/// Tasks waiting for input, or failed and not reviewed: the Activity count.

@ProviderFor(chatTaskAttention)
final chatTaskAttentionProvider = ChatTaskAttentionProvider._();

/// Tasks waiting for input, or failed and not reviewed: the Activity count.

final class ChatTaskAttentionProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatTaskPage>,
          AgentChatTaskPage,
          Stream<AgentChatTaskPage>
        >
    with
        $FutureModifier<AgentChatTaskPage>,
        $StreamProvider<AgentChatTaskPage> {
  /// Tasks waiting for input, or failed and not reviewed: the Activity count.
  ChatTaskAttentionProvider._()
    : super(
        from: null,
        argument: null,
        retry: chatTaskNoRetry,
        name: r'chatTaskAttentionProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatTaskAttentionHash();

  @$internal
  @override
  $StreamProviderElement<AgentChatTaskPage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<AgentChatTaskPage> create(Ref ref) {
    return chatTaskAttention(ref);
  }
}

String _$chatTaskAttentionHash() => r'290b0ae3cdb771c9bdd3d2a1ceedda7a1a1192e5';

/// One task, live. Reading it never acknowledges its result.

@ProviderFor(chatTaskDetail)
final chatTaskDetailProvider = ChatTaskDetailFamily._();

/// One task, live. Reading it never acknowledges its result.

final class ChatTaskDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatTask>,
          AgentChatTask,
          Stream<AgentChatTask>
        >
    with $FutureModifier<AgentChatTask>, $StreamProvider<AgentChatTask> {
  /// One task, live. Reading it never acknowledges its result.
  ChatTaskDetailProvider._({
    required ChatTaskDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: chatTaskNoRetry,
         name: r'chatTaskDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatTaskDetailHash();

  @override
  String toString() {
    return r'chatTaskDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<AgentChatTask> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<AgentChatTask> create(Ref ref) {
    final argument = this.argument as String;
    return chatTaskDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatTaskDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatTaskDetailHash() => r'9b12456043df07e1ba0316bef831507bf4f7a14b';

/// One task, live. Reading it never acknowledges its result.

final class ChatTaskDetailFamily extends $Family
    with $FunctionalFamilyOverride<Stream<AgentChatTask>, String> {
  ChatTaskDetailFamily._()
    : super(
        retry: chatTaskNoRetry,
        name: r'chatTaskDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One task, live. Reading it never acknowledges its result.

  ChatTaskDetailProvider call(String taskId) =>
      ChatTaskDetailProvider._(argument: taskId, from: this);

  @override
  String toString() => r'chatTaskDetailProvider';
}

/// The open requests of a task's child chat, read again whenever the task
/// changes.

@ProviderFor(chatTaskRequests)
final chatTaskRequestsProvider = ChatTaskRequestsFamily._();

/// The open requests of a task's child chat, read again whenever the task
/// changes.

final class ChatTaskRequestsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<AgentChatTaskRequest>>,
          List<AgentChatTaskRequest>,
          FutureOr<List<AgentChatTaskRequest>>
        >
    with
        $FutureModifier<List<AgentChatTaskRequest>>,
        $FutureProvider<List<AgentChatTaskRequest>> {
  /// The open requests of a task's child chat, read again whenever the task
  /// changes.
  ChatTaskRequestsProvider._({
    required ChatTaskRequestsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'chatTaskRequestsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatTaskRequestsHash();

  @override
  String toString() {
    return r'chatTaskRequestsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<AgentChatTaskRequest>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentChatTaskRequest>> create(Ref ref) {
    final argument = this.argument as String;
    return chatTaskRequests(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatTaskRequestsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatTaskRequestsHash() => r'365f4b2534e693e3fbfd3b6d1119f6e6dd43ce9c';

/// The open requests of a task's child chat, read again whenever the task
/// changes.

final class ChatTaskRequestsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<List<AgentChatTaskRequest>>,
          String
        > {
  ChatTaskRequestsFamily._()
    : super(
        retry: null,
        name: r'chatTaskRequestsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The open requests of a task's child chat, read again whenever the task
  /// changes.

  ChatTaskRequestsProvider call(String taskId) =>
      ChatTaskRequestsProvider._(argument: taskId, from: this);

  @override
  String toString() => r'chatTaskRequestsProvider';
}

/// Whether a delegation may choose the child's reasoning effort. Without it
/// no effort control appears.

@ProviderFor(chatTaskEffortSupported)
final chatTaskEffortSupportedProvider = ChatTaskEffortSupportedProvider._();

/// Whether a delegation may choose the child's reasoning effort. Without it
/// no effort control appears.

final class ChatTaskEffortSupportedProvider
    extends $FunctionalProvider<AsyncValue<bool>, bool, FutureOr<bool>>
    with $FutureModifier<bool>, $FutureProvider<bool> {
  /// Whether a delegation may choose the child's reasoning effort. Without it
  /// no effort control appears.
  ChatTaskEffortSupportedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatTaskEffortSupportedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatTaskEffortSupportedHash();

  @$internal
  @override
  $FutureProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<bool> create(Ref ref) {
    return chatTaskEffortSupported(ref);
  }
}

String _$chatTaskEffortSupportedHash() =>
    r'70428b57ab175c87b87eed9de66e31f7fe2f395d';

@ProviderFor(chatTaskCapabilities)
final chatTaskCapabilitiesProvider = ChatTaskCapabilitiesProvider._();

final class ChatTaskCapabilitiesProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatOrchestrationCapabilities>,
          AgentChatOrchestrationCapabilities,
          FutureOr<AgentChatOrchestrationCapabilities>
        >
    with
        $FutureModifier<AgentChatOrchestrationCapabilities>,
        $FutureProvider<AgentChatOrchestrationCapabilities> {
  ChatTaskCapabilitiesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatTaskCapabilitiesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatTaskCapabilitiesHash();

  @$internal
  @override
  $FutureProviderElement<AgentChatOrchestrationCapabilities> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatOrchestrationCapabilities> create(Ref ref) {
    return chatTaskCapabilities(ref);
  }
}

String _$chatTaskCapabilitiesHash() =>
    r'd4e14060888c0c7db591a40f46f682b8e2c573d7';

/// The agents a delegation can start: the providers of the workspace's own
/// host when it exists, else the runtime's catalog, with the runtime's
/// orchestration flags either way.

@ProviderFor(chatTaskAgentCatalog)
final chatTaskAgentCatalogProvider = ChatTaskAgentCatalogFamily._();

/// The agents a delegation can start: the providers of the workspace's own
/// host when it exists, else the runtime's catalog, with the runtime's
/// orchestration flags either way.

final class ChatTaskAgentCatalogProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatOrchestrationCapabilities>,
          AgentChatOrchestrationCapabilities,
          FutureOr<AgentChatOrchestrationCapabilities>
        >
    with
        $FutureModifier<AgentChatOrchestrationCapabilities>,
        $FutureProvider<AgentChatOrchestrationCapabilities> {
  /// The agents a delegation can start: the providers of the workspace's own
  /// host when it exists, else the runtime's catalog, with the runtime's
  /// orchestration flags either way.
  ChatTaskAgentCatalogProvider._({
    required ChatTaskAgentCatalogFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'chatTaskAgentCatalogProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatTaskAgentCatalogHash();

  @override
  String toString() {
    return r'chatTaskAgentCatalogProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatOrchestrationCapabilities> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatOrchestrationCapabilities> create(Ref ref) {
    final argument = this.argument as String?;
    return chatTaskAgentCatalog(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatTaskAgentCatalogProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatTaskAgentCatalogHash() =>
    r'1921317eb7e2455918bfc3f43b7c769de678b148';

/// The agents a delegation can start: the providers of the workspace's own
/// host when it exists, else the runtime's catalog, with the runtime's
/// orchestration flags either way.

final class ChatTaskAgentCatalogFamily extends $Family
    with
        $FunctionalFamilyOverride<
          FutureOr<AgentChatOrchestrationCapabilities>,
          String?
        > {
  ChatTaskAgentCatalogFamily._()
    : super(
        retry: null,
        name: r'chatTaskAgentCatalogProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The agents a delegation can start: the providers of the workspace's own
  /// host when it exists, else the runtime's catalog, with the runtime's
  /// orchestration flags either way.

  ChatTaskAgentCatalogProvider call(String? workspaceId) =>
      ChatTaskAgentCatalogProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'chatTaskAgentCatalogProvider';
}

/// Chats across every project and host, for the Existing Chat target.

@ProviderFor(chatTaskDirectory)
final chatTaskDirectoryProvider = ChatTaskDirectoryProvider._();

/// Chats across every project and host, for the Existing Chat target.

final class ChatTaskDirectoryProvider
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
  ChatTaskDirectoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatTaskDirectoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatTaskDirectoryHash();

  @$internal
  @override
  $FutureProviderElement<List<AgentChatDirectoryEntry>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<AgentChatDirectoryEntry>> create(Ref ref) {
    return chatTaskDirectory(ref);
  }
}

String _$chatTaskDirectoryHash() => r'07d1ae3c7b0b4e706a12fc60df5cc02e4e959fd6';

/// A chat's title and place, for the sender of a chat message.

@ProviderFor(chatTaskChat)
final chatTaskChatProvider = ChatTaskChatFamily._();

/// A chat's title and place, for the sender of a chat message.

final class ChatTaskChatProvider
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
  ChatTaskChatProvider._({
    required ChatTaskChatFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'chatTaskChatProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatTaskChatHash();

  @override
  String toString() {
    return r'chatTaskChatProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<AgentChatDirectoryEntry> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<AgentChatDirectoryEntry> create(Ref ref) {
    final argument = this.argument as String;
    return chatTaskChat(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatTaskChatProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatTaskChatHash() => r'6951580ae2a45d8d904dcef4ec8153678277ba64';

/// A chat's title and place, for the sender of a chat message.

final class ChatTaskChatFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<AgentChatDirectoryEntry>, String> {
  ChatTaskChatFamily._()
    : super(
        retry: null,
        name: r'chatTaskChatProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A chat's title and place, for the sender of a chat message.

  ChatTaskChatProvider call(String chatId) =>
      ChatTaskChatProvider._(argument: chatId, from: this);

  @override
  String toString() => r'chatTaskChatProvider';
}
