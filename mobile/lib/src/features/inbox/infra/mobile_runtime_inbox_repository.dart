import 'package:alera_mobile/src/core/json_payload_fields.dart';
import 'package:alera_mobile/src/features/inbox/domain/inbox_models.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

/// The runtime announces every inbox change, phones included, with this event
/// and a revision; screens reload what they show when it arrives.
const String inboxChangedEvent = 'inboxChanged';

class MobileRuntimeInboxRepository(final MobileInboxClient _client) {
  Stream<MobileRuntimeEvent> get changes =>
      _client.events.where((event) => event.name == inboxChangedEvent);

  Future<List<InboxSummaryEntry>> summary() async {
    final payload = await _client.requestMap('inbox.summary');
    return <InboxSummaryEntry>[
      for (final item in payload.objectList('items'))
        InboxSummaryEntry.fromJson(asJsonMap(item)),
    ];
  }

  Future<InboxThreadPage> threads({
    String? inbox,
    String? workspaceId,
    InboxQuestionStatus? status,
    int? before,
    int limit = 100,
  }) async {
    final payload = await _client.requestMap('inbox.threads', <String, Object?>{
      'inbox': ?inbox,
      'workspaceId': ?workspaceId,
      'status': ?status?.name,
      'before': ?before,
      'limit': limit,
    });
    return InboxThreadPage.fromJson(payload);
  }

  /// Loads a thread without acknowledging it. Replies are marked read with
  /// [markRead] only once someone is actually looking at them.
  Future<InboxThreadDetail> thread(String threadId) async {
    final payload = await _client.requestMap('inbox.thread', <String, Object?>{
      'threadId': threadId,
    });
    return InboxThreadDetail.fromJson(payload);
  }

  Future<List<InboxRecipient>> targets({String? workspaceId}) async {
    final payload = await _client.requestMap('inbox.targets', <String, Object?>{
      'workspaceId': ?workspaceId,
    });
    return <InboxRecipient>[
      for (final item in payload.objectList('items'))
        InboxRecipient.fromJson(asJsonMap(item)),
    ];
  }

  /// Asks [to] from [inbox] (the shared `ext:user` by default), or follows up
  /// in [threadId]. A follow-up sends no inbox unless one is named: the
  /// runtime keeps the thread's own inbox, which may be another one such as a
  /// CLI's `ext:ci`.
  Future<InboxAskResult> ask({
    required String body,
    String? to,
    String? threadId,
    String? subject,
    String? inbox,
  }) async {
    final payload = await _client.requestMap('inbox.ask', <String, Object?>{
      'inbox': ?(inbox ?? (threadId == null ? userInboxAddress : null)),
      'body': body,
      'to': ?to,
      'threadId': ?threadId,
      if (subject != null && subject.trim().isNotEmpty)
        'subject': subject.trim(),
    });
    return InboxAskResult.fromJson(payload);
  }

  Future<void> cancel(String questionId) => _client.requestMap(
    'inbox.cancel',
    <String, Object?>{'questionId': questionId},
  );

  Future<void> markRead(String threadId) => _client.requestMap(
    'inbox.markRead',
    <String, Object?>{'threadId': threadId},
  );

  Future<int> purge(String inbox) async {
    final payload = await _client.requestMap('inbox.purge', <String, Object?>{
      'inbox': inbox,
    });
    final deleted = payload['deleted'];
    return deleted is int ? deleted : 0;
  }
}
