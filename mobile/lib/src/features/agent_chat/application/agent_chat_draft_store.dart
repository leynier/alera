import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_repository.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_draft_submission.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/infra/local_agent_chat_draft_repository.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

export 'agent_chat_draft_repository.dart' show AgentChatDraftKey;

part 'agent_chat_draft_store.g.dart';

/// Device-local drafts and uploads that outlive a composer or host connection.
class AgentChatDraftStore {
  AgentChatDraftStore({this._repository});

  static final Logger _logger = Logger('AgentChatDraftStore');
  static const Duration _saveDelay = Duration(milliseconds: 200);
  static const Duration _loadTimeout = Duration(seconds: 2);
  final AgentChatDraftRepository? _repository;
  final Map<AgentChatDraftKey, AgentChatComposerDraft> _drafts = {};
  final Map<AgentChatDraftKey, AgentChatSubmissionIds> _submissions = {};
  final Map<AgentChatDraftKey, Map<String, AgentChatDraftSubmission>> _pending =
      {};
  final Map<AgentChatDraftKey, Set<String>> _settled = {};
  final Map<AgentChatDraftKey, Set<VoidCallback>> _listeners = {};
  final Map<AgentChatDraftKey, int> _revisions = {};
  final Map<AgentChatDraftKey, Future<AgentChatComposerDraft>> _loads = {};
  final Set<AgentChatDraftKey> _loadFailures = {};
  final Set<AgentChatDraftKey> _closed = {};
  final Set<AgentChatDraftKey> _dirty = {};
  Timer? _timer;
  Future<void>? _saving;

  AgentChatComposerDraft read(
    String hostId,
    String chatId, {
    String workspaceId = '',
  }) =>
      _drafts[_key(hostId, chatId, workspaceId)] ??
      const AgentChatComposerDraft();

  Future<AgentChatComposerDraft> hydrate(
    String hostId,
    String chatId, {
    String workspaceId = '',
  }) {
    final key = _key(hostId, chatId, workspaceId);
    final loading = _loads.putIfAbsent(
      key,
      () => _load(key).whenComplete(() {
        if (_loadFailures.contains(key)) _loads.remove(key);
      }),
    );
    return loading.then((_) => _drafts[key] ?? const AgentChatComposerDraft());
  }

  Future<AgentChatComposerDraft> _load(AgentChatDraftKey key) async {
    final revision = _revisions[key] ?? 0;
    try {
      final snapshot = await _repository?.load(key).timeout(_loadTimeout);
      if (snapshot != null && !_closed.contains(key)) {
        final decoded = jsonDecode(snapshot) as Map<String, dynamic>;
        if (decoded['version'] != 1) {
          throw const FormatException('Unsupported chat draft version.');
        }
        final draft = _decodeDraft(decoded['draft']);
        for (final pending in decoded['pending'] as List? ?? const []) {
          final submission = _decodeSubmission(pending);
          if (!(_settled[key]?.contains(submission.clientMessageId) ?? false)) {
            _pending
                .putIfAbsent(key, () => {})
                .putIfAbsent(submission.clientMessageId, () => submission);
          }
        }
        if ((_revisions[key] ?? 0) == revision && !draft.isEmpty) {
          _drafts[key] = draft;
        }
        _submissions
            .putIfAbsent(key, AgentChatSubmissionIds.new)
            .restore(
              Map<String, String>.from(decoded['ids'] as Map? ?? const {})
                ..removeWhere((_, id) => _settled[key]?.contains(id) ?? false),
            );
        _notify(key);
      }
      _loadFailures.remove(key);
    } on Object catch (error, stackTrace) {
      _loadFailures.add(key);
      _logger.warning('Could not restore chat draft.', error, stackTrace);
    }
    return _drafts[key] ?? const AgentChatComposerDraft();
  }

  Future<void> ensureHydrated(
    String hostId,
    String chatId, {
    String workspaceId = '',
  }) async {
    await hydrate(hostId, chatId, workspaceId: workspaceId);
    if (_loadFailures.contains(_key(hostId, chatId, workspaceId))) {
      throw StateError('Chat drafts could not be read. Try again.');
    }
  }

  void write(
    String hostId,
    String chatId,
    AgentChatComposerDraft draft, {
    String workspaceId = '',
  }) {
    final key = _key(hostId, chatId, workspaceId);
    if (_closed.contains(key)) return;
    if (draft.isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = draft;
    }
    _changed(key);
  }

  /// Appends a finished upload and notifies the mounted composer, if any.
  void addAttachment(
    String hostId,
    String chatId,
    AgentChatDraftAttachment attachment, {
    String workspaceId = '',
  }) {
    final current = read(hostId, chatId, workspaceId: workspaceId);
    if (current.attachments.contains(attachment)) return;
    _update(
      hostId,
      chatId,
      current.copyWith(
        attachments: <AgentChatDraftAttachment>[
          ...current.attachments,
          attachment,
        ],
      ),
      workspaceId: workspaceId,
    );
  }

  /// Returns a submission the runtime did not accept to the composer.
  void restore(
    String hostId,
    String chatId,
    AgentChatComposerDraft submission, {
    String workspaceId = '',
  }) {
    _pending[_key(hostId, chatId, workspaceId)]?.removeWhere(
      (_, pending) => pending.draft.signature == submission.signature,
    );
    _update(
      hostId,
      chatId,
      read(hostId, chatId, workspaceId: workspaceId).restoring(submission),
      workspaceId: workspaceId,
    );
  }

  AgentChatSubmissionIds submissionIds(
    String hostId,
    String chatId, {
    String workspaceId = '',
  }) => _submissions.putIfAbsent(
    _key(hostId, chatId, workspaceId),
    AgentChatSubmissionIds.new,
  );

  void beginSubmission(
    String hostId,
    String chatId,
    String clientMessageId,
    AgentChatComposerDraft draft, {
    String workspaceId = '',
    String? model,
    String? reasoningEffort,
    AgentChatInteractionMode? interactionMode,
    AgentChatDelivery delivery = AgentChatDelivery.auto,
    DateTime? createdAt,
    bool replaceOptions = false,
    List<AgentChatAttachment>? messageAttachments,
  }) {
    final key = _key(hostId, chatId, workspaceId);
    if (_closed.contains(key)) return;
    final current = _drafts[key];
    _submissions.putIfAbsent(key, AgentChatSubmissionIds.new).restore({
      draft.signature: clientMessageId,
    });
    final pending = _pending.putIfAbsent(key, () => {});
    final existing = pending[clientMessageId];
    if (existing == null || replaceOptions) {
      pending[clientMessageId] = AgentChatDraftSubmission(
        clientMessageId: clientMessageId,
        draft:
            existing?.draft ??
            (current?.signature == draft.signature ? current! : draft),
        createdAt: createdAt ?? existing?.createdAt ?? DateTime.now().toUtc(),
        model: model,
        reasoningEffort: reasoningEffort,
        interactionMode: interactionMode,
        delivery: delivery,
        attachments: messageAttachments,
      );
    }
    _changed(key);
  }

  /// Runtime acceptance or an explicit edit settles the retained submission.
  void settleSubmission(
    String hostId,
    String chatId,
    String clientMessageId, {
    String workspaceId = '',
  }) {
    final key = _key(hostId, chatId, workspaceId);
    _pending[key]?.remove(clientMessageId);
    _settled.putIfAbsent(key, () => {}).add(clientMessageId);
    _submissions[key]?.settledId(clientMessageId);
    _changed(key);
  }

  List<AgentChatDraftSubmission> pending(
    String hostId,
    String chatId, {
    String workspaceId = '',
  }) => List<AgentChatDraftSubmission>.unmodifiableOf(
    _pending[_key(hostId, chatId, workspaceId)]?.values ?? const [],
  );

  void addListener(
    String hostId,
    String chatId,
    VoidCallback listener, {
    String workspaceId = '',
  }) => _listeners
      .putIfAbsent(_key(hostId, chatId, workspaceId), () => {})
      .add(listener);

  void removeListener(
    String hostId,
    String chatId,
    VoidCallback listener, {
    String workspaceId = '',
  }) {
    final key = _key(hostId, chatId, workspaceId);
    _listeners[key]?.remove(listener);
    if (_listeners[key]?.isEmpty ?? false) _listeners.remove(key);
  }

  void activate(String hostId, String chatId, {String workspaceId = ''}) =>
      _closed.remove(_key(hostId, chatId, workspaceId));

  /// An accepted close discards the draft and blocks late uploads.
  void close(String hostId, String chatId, {String workspaceId = ''}) {
    final key = _key(hostId, chatId, workspaceId);
    _drafts.remove(key);
    _submissions.remove(key);
    _pending.remove(key);
    _closed.add(key);
    _changed(key);
  }

  void _update(
    String hostId,
    String chatId,
    AgentChatComposerDraft draft, {
    required String workspaceId,
  }) {
    final key = _key(hostId, chatId, workspaceId);
    if (_closed.contains(key)) return;
    write(hostId, chatId, draft, workspaceId: workspaceId);
    _notify(key);
  }

  void _notify(AgentChatDraftKey key) {
    for (final listener in List<VoidCallback>.of(_listeners[key] ?? const {})) {
      listener();
    }
  }

  void _changed(AgentChatDraftKey key) {
    _revisions[key] = (_revisions[key] ?? 0) + 1;
    if (_repository == null) return;
    _dirty.add(key);
    _timer?.cancel();
    _timer = Timer(_saveDelay, () => unawaited(flush()));
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _saving ??= _drain().whenComplete(() => _saving = null);
  }

  Future<void> flushSubmission(
    String hostId,
    String chatId, {
    String workspaceId = '',
  }) async {
    await flush();
    if (_dirty.contains(_key(hostId, chatId, workspaceId))) {
      throw StateError('The message draft could not be saved. Try again.');
    }
  }

  Future<void> _drain() async {
    final failed = <AgentChatDraftKey>{};
    while (_dirty.any((key) => !failed.contains(key))) {
      final key = _dirty.firstWhere((key) => !failed.contains(key));
      await hydrate(key.hostId, key.chatId, workspaceId: key.workspaceId);
      if (_loadFailures.contains(key) && !_closed.contains(key)) {
        failed.add(key);
        continue;
      }
      _dirty.remove(key);
      final draft = _drafts[key] ?? const AgentChatComposerDraft();
      final pending = _pending[key] ?? const {};
      final snapshot = draft.isEmpty && pending.isEmpty
          ? null
          : jsonEncode({
              'version': 1,
              'draft': _encodeDraft(draft),
              'pending': <Object>[
                for (final entry in pending.entries)
                  _encodeSubmission(entry.value),
              ],
              'ids': _submissions[key]?.snapshot ?? const {},
            });
      try {
        await _repository?.save(key, snapshot);
      } on Object catch (error, stackTrace) {
        failed.add(key);
        _dirty.add(key);
        _logger.warning('Could not save chat draft.', error, stackTrace);
      }
    }
  }

  AgentChatDraftKey _key(String hostId, String chatId, String workspaceId) =>
      (hostId: hostId, workspaceId: workspaceId, chatId: chatId);

  Map<String, Object?> _encodeDraft(AgentChatComposerDraft draft) => {
    'text': draft.value.text,
    'selectionBase': draft.value.selection.baseOffset,
    'selectionExtent': draft.value.selection.extentOffset,
    'attachments': <Object>[
      for (final attachment in draft.attachments)
        {
          'source': attachment.source.name,
          'path': attachment.path,
          'displayName': attachment.displayName,
          'attachmentId': attachment.attachmentId,
          'sizeBytes': attachment.sizeBytes,
        },
    ],
  };

  AgentChatComposerDraft _decodeDraft(dynamic value) {
    final decoded = value as Map;
    final text = decoded['text'] as String;
    return AgentChatComposerDraft(
      value: TextEditingValue(
        text: text,
        selection: TextSelection(
          baseOffset: (decoded['selectionBase'] as int).clamp(-1, text.length),
          extentOffset: (decoded['selectionExtent'] as int).clamp(
            -1,
            text.length,
          ),
        ),
      ),
      attachments: <AgentChatDraftAttachment>[
        for (final attachment in decoded['attachments'] as List)
          AgentChatDraftAttachment(
            source: AgentChatAttachmentSource.values.byName(
              attachment['source'] as String,
            ),
            path: attachment['path'] as String,
            displayName: attachment['displayName'] as String,
            attachmentId: attachment['attachmentId'] as String?,
            sizeBytes: attachment['sizeBytes'] as int?,
          ),
      ],
    );
  }

  Map<String, Object?> _encodeSubmission(
    AgentChatDraftSubmission submission,
  ) => {
    'id': submission.clientMessageId,
    'draft': _encodeDraft(submission.draft),
    'createdAt': submission.createdAt.toIso8601String(),
    'model': submission.model,
    'reasoningEffort': submission.reasoningEffort,
    'interactionMode': submission.interactionMode?.wire,
    'delivery': submission.delivery.wire,
    'attachments': <Object>[
      for (final attachment in submission.input('', '').attachments)
        {...attachment.toJson(), 'localSourcePath': attachment.localSourcePath},
    ],
  };

  AgentChatDraftSubmission _decodeSubmission(dynamic value) =>
      AgentChatDraftSubmission(
        clientMessageId: value['id'] as String,
        draft: _decodeDraft(value['draft']),
        createdAt: DateTime.parse(value['createdAt'] as String),
        model: value['model'] as String?,
        reasoningEffort: value['reasoningEffort'] as String?,
        interactionMode: AgentChatInteractionMode.tryParse(
          value['interactionMode'],
        ),
        delivery: AgentChatDelivery.values.singleWhere(
          (delivery) => delivery.wire == value['delivery'],
        ),
        attachments: value['attachments'] == null
            ? null
            : <AgentChatAttachment>[
                for (final attachment in value['attachments'] as List)
                  AgentChatAttachment.fromJson(attachment, localDraft: true),
              ],
      );
}

@Riverpod(keepAlive: true)
AgentChatDraftStore agentChatDraftStore(Ref ref) {
  final store = AgentChatDraftStore(
    repository: LocalAgentChatDraftRepository(),
  );
  ref.onDispose(() => unawaited(store.flush()));
  return store;
}
