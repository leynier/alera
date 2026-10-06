import 'package:alera/src/features/inbox/domain/conversation_models.dart';
import 'package:alera/src/features/inbox/domain/inbox_error_messages.dart';
import 'package:alera/src/features/inbox/domain/inbox_models.dart';
import 'package:alera/src/features/inbox/infra/inbox_watch.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';

/// Filters of the thread list. A null [inbox] lists every inbox.
class const InboxThreadQuery({
  final String? inbox,
  final InboxQuestionStatus? status,
  final int limit = 100,

  /// Continues a listing from the previous page's `nextBefore`.
  final int? before,
}) {
  Map<String, Object?> toJson() => <String, Object?>{
    'inbox': ?inbox,
    'status': ?status?.key,
    'limit': limit,
    'before': ?before,
  };

  String get cacheKey => '${inbox ?? '*'}:${status?.key ?? '*'}:$limit';
}

/// The desktop is a local runtime client, so every `inbox.*` verb is allowed.
class RuntimeInboxRepository {
  RuntimeInboxRepository(this._client, this._coalescer);

  final RuntimeHostClient _client;
  final RuntimeChangeCoalescer _coalescer;

  Future<bool> supported() async {
    final client = _client;
    return client is RuntimeHostCapabilityClient &&
        await (client as RuntimeHostCapabilityClient).supportsRuntimeCapability(
          aleraRuntimeHostInboxCapability,
        );
  }

  Future<Map<String, Object?>> _request(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    if (!await supported()) throw const InboxUpdateRequired();
    final response = await _client.runtimeRequest(type, payload);
    return response is Map
        ? Map<String, Object?>.from(response)
        : const <String, Object?>{};
  }

  Future<InboxSummary> readSummary() async =>
      InboxSummary.fromJson(await _request('inbox.summary'));

  Future<InboxThreadPage> readThreads([
    InboxThreadQuery query = const InboxThreadQuery(),
  ]) async =>
      InboxThreadPage.fromJson(await _request('inbox.threads', query.toJson()));

  Future<InboxThreadDetail> readThread(
    String threadId, {
    bool markRead = false,
  }) async => InboxThreadDetail.fromJson(
    await _request('inbox.thread', <String, Object?>{
      'threadId': threadId,
      'markRead': markRead,
    }),
  );

  Future<List<InboxRecipient>> readTargets() async =>
      parseInboxTargets(await _request('inbox.targets'));

  /// Returns the new question's thread id.
  Future<String> ask(InboxAskRequest request) async {
    final response = await _request('inbox.ask', request.toJson());
    return response['threadId'] as String? ?? '';
  }

  Future<void> cancel(String questionId) =>
      _request('inbox.cancel', <String, Object?>{'questionId': questionId});

  Future<void> markRead(String threadId) =>
      _request('inbox.markRead', <String, Object?>{'threadId': threadId});

  Future<int> purge(String inbox) async {
    final response = await _request('inbox.purge', <String, Object?>{
      'inbox': inbox,
    });
    return (response['deleted'] as num?)?.toInt() ?? 0;
  }

  Stream<InboxSummary> watchSummary() => watchInbox(
    client: _client,
    coalescer: _coalescer,
    key: 'inbox-summary',
    read: readSummary,
  );

  Stream<InboxThreadPage> watchThreads(InboxThreadQuery query) => watchInbox(
    client: _client,
    coalescer: _coalescer,
    key: 'inbox-threads:${query.cacheKey}',
    read: () => readThreads(query),
  );

  /// Loading never acknowledges: a refresh can arrive while the window is
  /// hidden. The detail view marks replies read once the user can see them.
  Stream<InboxThreadDetail> watchThread(String threadId) => watchInbox(
    client: _client,
    coalescer: _coalescer,
    key: 'inbox-thread:$threadId',
    read: () => readThread(threadId),
  );

  /// Agent-to-agent threads. Read-only: nothing here marks anything read.
  Future<ConversationPage> readConversations({
    String? workspaceId,
    int? before,
  }) async => ConversationPage.fromJson(
    await _request('inbox.conversations', <String, Object?>{
      'workspaceId': ?workspaceId,
      'limit': 100,
      'before': ?before,
    }),
  );

  Future<ConversationDetail> readConversation(String threadId) async =>
      ConversationDetail.fromJson(
        await _request('inbox.conversation', <String, Object?>{
          'threadId': threadId,
        }),
      );

  Stream<ConversationPage> watchConversations({String? workspaceId}) =>
      watchInbox(
        client: _client,
        coalescer: _coalescer,
        key: 'conversations:${workspaceId ?? '*'}',
        read: () => readConversations(workspaceId: workspaceId),
        changedEvent: conversationsChangedEvent,
      );

  Stream<ConversationDetail> watchConversation(String threadId) => watchInbox(
    client: _client,
    coalescer: _coalescer,
    key: 'conversation:$threadId',
    read: () => readConversation(threadId),
    changedEvent: conversationsChangedEvent,
  );
}
