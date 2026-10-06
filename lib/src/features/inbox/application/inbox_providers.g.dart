// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(inboxRepository)
final inboxRepositoryProvider = InboxRepositoryProvider._();

final class InboxRepositoryProvider
    extends
        $FunctionalProvider<
          RuntimeInboxRepository,
          RuntimeInboxRepository,
          RuntimeInboxRepository
        >
    with $Provider<RuntimeInboxRepository> {
  InboxRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inboxRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inboxRepositoryHash();

  @$internal
  @override
  $ProviderElement<RuntimeInboxRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RuntimeInboxRepository create(Ref ref) {
    return inboxRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RuntimeInboxRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RuntimeInboxRepository>(value),
    );
  }
}

String _$inboxRepositoryHash() => r'30fc85752a901adf8da06d556bab1ef40fc17c42';

@ProviderFor(inboxSummary)
final inboxSummaryProvider = InboxSummaryProvider._();

final class InboxSummaryProvider
    extends
        $FunctionalProvider<
          AsyncValue<InboxSummary>,
          InboxSummary,
          Stream<InboxSummary>
        >
    with $FutureModifier<InboxSummary>, $StreamProvider<InboxSummary> {
  InboxSummaryProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noInboxRetry,
        name: r'inboxSummaryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inboxSummaryHash();

  @$internal
  @override
  $StreamProviderElement<InboxSummary> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<InboxSummary> create(Ref ref) {
    return inboxSummary(ref);
  }
}

String _$inboxSummaryHash() => r'dcf28a9318cfc51e1ea030d197f590ef547697f0';

@ProviderFor(inboxThreads)
final inboxThreadsProvider = InboxThreadsFamily._();

final class InboxThreadsProvider
    extends
        $FunctionalProvider<
          AsyncValue<InboxThreadPage>,
          InboxThreadPage,
          Stream<InboxThreadPage>
        >
    with $FutureModifier<InboxThreadPage>, $StreamProvider<InboxThreadPage> {
  InboxThreadsProvider._({
    required InboxThreadsFamily super.from,
    required ({String? inbox, InboxQuestionStatus? status}) super.argument,
  }) : super(
         retry: _noInboxRetry,
         name: r'inboxThreadsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$inboxThreadsHash();

  @override
  String toString() {
    return r'inboxThreadsProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  $StreamProviderElement<InboxThreadPage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<InboxThreadPage> create(Ref ref) {
    final argument =
        this.argument as ({String? inbox, InboxQuestionStatus? status});
    return inboxThreads(ref, inbox: argument.inbox, status: argument.status);
  }

  @override
  bool operator ==(Object other) {
    return other is InboxThreadsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$inboxThreadsHash() => r'9af8f042ccb739c3ad0f921f0a3dd466a30bb721';

final class InboxThreadsFamily extends $Family
    with
        $FunctionalFamilyOverride<
          Stream<InboxThreadPage>,
          ({String? inbox, InboxQuestionStatus? status})
        > {
  InboxThreadsFamily._()
    : super(
        retry: _noInboxRetry,
        name: r'inboxThreadsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  InboxThreadsProvider call({String? inbox, InboxQuestionStatus? status}) =>
      InboxThreadsProvider._(
        argument: (inbox: inbox, status: status),
        from: this,
      );

  @override
  String toString() => r'inboxThreadsProvider';
}

@ProviderFor(inboxThreadDetail)
final inboxThreadDetailProvider = InboxThreadDetailFamily._();

final class InboxThreadDetailProvider
    extends
        $FunctionalProvider<
          AsyncValue<InboxThreadDetail>,
          InboxThreadDetail,
          Stream<InboxThreadDetail>
        >
    with
        $FutureModifier<InboxThreadDetail>,
        $StreamProvider<InboxThreadDetail> {
  InboxThreadDetailProvider._({
    required InboxThreadDetailFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noInboxRetry,
         name: r'inboxThreadDetailProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$inboxThreadDetailHash();

  @override
  String toString() {
    return r'inboxThreadDetailProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<InboxThreadDetail> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<InboxThreadDetail> create(Ref ref) {
    final argument = this.argument as String;
    return inboxThreadDetail(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is InboxThreadDetailProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$inboxThreadDetailHash() => r'578be79b2ac1fa7725098c26a3c3d34fe75d1433';

final class InboxThreadDetailFamily extends $Family
    with $FunctionalFamilyOverride<Stream<InboxThreadDetail>, String> {
  InboxThreadDetailFamily._()
    : super(
        retry: _noInboxRetry,
        name: r'inboxThreadDetailProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  InboxThreadDetailProvider call(String threadId) =>
      InboxThreadDetailProvider._(argument: threadId, from: this);

  @override
  String toString() => r'inboxThreadDetailProvider';
}

@ProviderFor(inboxTargets)
final inboxTargetsProvider = InboxTargetsProvider._();

final class InboxTargetsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<InboxRecipient>>,
          List<InboxRecipient>,
          FutureOr<List<InboxRecipient>>
        >
    with
        $FutureModifier<List<InboxRecipient>>,
        $FutureProvider<List<InboxRecipient>> {
  InboxTargetsProvider._()
    : super(
        from: null,
        argument: null,
        retry: _noInboxRetry,
        name: r'inboxTargetsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inboxTargetsHash();

  @$internal
  @override
  $FutureProviderElement<List<InboxRecipient>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<InboxRecipient>> create(Ref ref) {
    return inboxTargets(ref);
  }
}

String _$inboxTargetsHash() => r'e80f269782defa5b6311965ab6ce77dcba308fc2';

/// Unread replies across every inbox, or null when the host cannot answer.

@ProviderFor(inboxUnreadReplyCount)
final inboxUnreadReplyCountProvider = InboxUnreadReplyCountProvider._();

/// Unread replies across every inbox, or null when the host cannot answer.

final class InboxUnreadReplyCountProvider
    extends $FunctionalProvider<int?, int?, int?>
    with $Provider<int?> {
  /// Unread replies across every inbox, or null when the host cannot answer.
  InboxUnreadReplyCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inboxUnreadReplyCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inboxUnreadReplyCountHash();

  @$internal
  @override
  $ProviderElement<int?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  int? create(Ref ref) {
    return inboxUnreadReplyCount(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int?>(value),
    );
  }
}

String _$inboxUnreadReplyCountHash() =>
    r'47a6c99c6e33fdb0098eb04dcbb7b588ab6bf568';

/// Whether the user can see and act on the app window: visible and focused.
/// Reading a reply and suppressing its notification both depend on it.

@ProviderFor(inboxWindowFocus)
final inboxWindowFocusProvider = InboxWindowFocusProvider._();

/// Whether the user can see and act on the app window: visible and focused.
/// Reading a reply and suppressing its notification both depend on it.

final class InboxWindowFocusProvider
    extends $FunctionalProvider<AppForeground, AppForeground, AppForeground>
    with $Provider<AppForeground> {
  /// Whether the user can see and act on the app window: visible and focused.
  /// Reading a reply and suppressing its notification both depend on it.
  InboxWindowFocusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'inboxWindowFocusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$inboxWindowFocusHash();

  @$internal
  @override
  $ProviderElement<AppForeground> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppForeground create(Ref ref) {
    return inboxWindowFocus(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppForeground value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppForeground>(value),
    );
  }
}

String _$inboxWindowFocusHash() => r'3516b717804000b78cbce74a4cc60161f86c36f6';

@ProviderFor(agentConversations)
final agentConversationsProvider = AgentConversationsFamily._();

final class AgentConversationsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConversationPage>,
          ConversationPage,
          Stream<ConversationPage>
        >
    with $FutureModifier<ConversationPage>, $StreamProvider<ConversationPage> {
  AgentConversationsProvider._({
    required AgentConversationsFamily super.from,
    required String? super.argument,
  }) : super(
         retry: _noInboxRetry,
         name: r'agentConversationsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentConversationsHash();

  @override
  String toString() {
    return r'agentConversationsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<ConversationPage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ConversationPage> create(Ref ref) {
    final argument = this.argument as String?;
    return agentConversations(ref, workspaceId: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentConversationsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentConversationsHash() =>
    r'b634c4e9a3eca5a6c646a3937b6828d92c117224';

final class AgentConversationsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<ConversationPage>, String?> {
  AgentConversationsFamily._()
    : super(
        retry: _noInboxRetry,
        name: r'agentConversationsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentConversationsProvider call({String? workspaceId}) =>
      AgentConversationsProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'agentConversationsProvider';
}

@ProviderFor(agentConversation)
final agentConversationProvider = AgentConversationFamily._();

final class AgentConversationProvider
    extends
        $FunctionalProvider<
          AsyncValue<ConversationDetail>,
          ConversationDetail,
          Stream<ConversationDetail>
        >
    with
        $FutureModifier<ConversationDetail>,
        $StreamProvider<ConversationDetail> {
  AgentConversationProvider._({
    required AgentConversationFamily super.from,
    required String super.argument,
  }) : super(
         retry: _noInboxRetry,
         name: r'agentConversationProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$agentConversationHash();

  @override
  String toString() {
    return r'agentConversationProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<ConversationDetail> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ConversationDetail> create(Ref ref) {
    final argument = this.argument as String;
    return agentConversation(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is AgentConversationProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$agentConversationHash() => r'b2634941bf501e9160fb5ac353f194431d3ca58c';

final class AgentConversationFamily extends $Family
    with $FunctionalFamilyOverride<Stream<ConversationDetail>, String> {
  AgentConversationFamily._()
    : super(
        retry: _noInboxRetry,
        name: r'agentConversationProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AgentConversationProvider call(String threadId) =>
      AgentConversationProvider._(argument: threadId, from: this);

  @override
  String toString() => r'agentConversationProvider';
}
