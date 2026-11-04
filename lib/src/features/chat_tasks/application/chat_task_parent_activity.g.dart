// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_task_parent_activity.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One runtime-wide list of unsettled tasks, read again on every change that
/// may touch it. The app-wide notification coordinator keeps it alive;
/// hidden windows do no reads.

@ProviderFor(chatTaskOpenTasks)
final chatTaskOpenTasksProvider = ChatTaskOpenTasksProvider._();

/// One runtime-wide list of unsettled tasks, read again on every change that
/// may touch it. The app-wide notification coordinator keeps it alive;
/// hidden windows do no reads.

final class ChatTaskOpenTasksProvider
    extends
        $FunctionalProvider<
          AsyncValue<AgentChatTaskPage>,
          AgentChatTaskPage,
          Stream<AgentChatTaskPage>
        >
    with
        $FutureModifier<AgentChatTaskPage>,
        $StreamProvider<AgentChatTaskPage> {
  /// One runtime-wide list of unsettled tasks, read again on every change that
  /// may touch it. The app-wide notification coordinator keeps it alive;
  /// hidden windows do no reads.
  ChatTaskOpenTasksProvider._()
    : super(
        from: null,
        argument: null,
        retry: chatTaskNoRetry,
        name: r'chatTaskOpenTasksProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatTaskOpenTasksHash();

  @$internal
  @override
  $StreamProviderElement<AgentChatTaskPage> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<AgentChatTaskPage> create(Ref ref) {
    return chatTaskOpenTasks(ref);
  }
}

String _$chatTaskOpenTasksHash() => r'5b0c7d32cceca7f4f19e6ff861db38b94ad8ba93';

/// What each parent chat waits on, keyed by parent chat id. Empty on a
/// runtime without chat tasks or while a read fails.

@ProviderFor(chatTaskParentActivity)
final chatTaskParentActivityProvider = ChatTaskParentActivityProvider._();

/// What each parent chat waits on, keyed by parent chat id. Empty on a
/// runtime without chat tasks or while a read fails.

final class ChatTaskParentActivityProvider
    extends
        $FunctionalProvider<
          Map<String, ChatTaskParentActivity>,
          Map<String, ChatTaskParentActivity>,
          Map<String, ChatTaskParentActivity>
        >
    with $Provider<Map<String, ChatTaskParentActivity>> {
  /// What each parent chat waits on, keyed by parent chat id. Empty on a
  /// runtime without chat tasks or while a read fails.
  ChatTaskParentActivityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'chatTaskParentActivityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatTaskParentActivityHash();

  @$internal
  @override
  $ProviderElement<Map<String, ChatTaskParentActivity>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, ChatTaskParentActivity> create(Ref ref) {
    return chatTaskParentActivity(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, ChatTaskParentActivity> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, ChatTaskParentActivity>>(
        value,
      ),
    );
  }
}

String _$chatTaskParentActivityHash() =>
    r'10aa8aef70a014ef7ddc76971ef310dbbf72de81';
