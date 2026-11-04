import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/agent_chat/application/agent_chat_draft_repository.dart';
import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

final class const AgentChatComposerDraft({
  final String text = '',
  final List<TerminalComposerAttachment> attachments =
      const <TerminalComposerAttachment>[],
}) {
  static const AgentChatComposerDraft empty = AgentChatComposerDraft();

  bool get isEmpty => text.isEmpty && attachments.isEmpty;

  String get signature => jsonEncode(<Object?>[
    text.trim(),
    for (final attachment in attachments)
      <Object?>[
        attachment.kind.name,
        attachment.path,
        attachment.displayName,
        attachment.attachmentId,
        attachment.sizeBytes,
      ],
  ]);

  factory fromMessage(String text, List<AgentChatAttachment> attachments) =>
      AgentChatComposerDraft(
        text: text,
        attachments: <TerminalComposerAttachment>[
          for (final (index, attachment) in attachments.indexed)
            TerminalComposerAttachment(
              id: 'restored-$index',
              kind: attachment.type.isImage ? .image : .file,
              path: attachment.path ?? attachment.url ?? '',
              displayName: attachment.displayName,
              localSourcePath: attachment.localSourcePath,
              attachmentId: attachment.attachmentId,
              sizeBytes: attachment.sizeBytes,
            ),
        ],
      );

  AgentChatComposerDraft restoring(AgentChatComposerDraft other) =>
      AgentChatComposerDraft(
        text: <String>[
          if (text.isNotEmpty) text,
          if (other.text.isNotEmpty) other.text,
        ].join('\n\n'),
        attachments: <TerminalComposerAttachment>[
          ...attachments,
          for (final attachment in other.attachments)
            if (!attachments.any(
              (current) =>
                  current.path == attachment.path &&
                  current.kind == attachment.kind,
            ))
              attachment,
        ],
      );
}

final class const AgentChatDraftSubmission({
  required final String clientMessageId,
  required final AgentChatComposerDraft draft,
  required final DateTime createdAt,
  final String? model,
  final String? reasoningEffort,
  final AgentChatInteractionMode? interactionMode,
  final AgentChatDelivery delivery = AgentChatDelivery.auto,
  final List<AgentChatAttachment>? attachments,
}) {
  AgentChatSendInput input(String chatId, String workspaceId) =>
      AgentChatSendInput(
        chatId: chatId,
        workspaceId: workspaceId,
        clientMessageId: clientMessageId,
        text: draft.text.trim(),
        model: model,
        reasoningEffort: reasoningEffort,
        interactionMode: interactionMode,
        delivery: delivery,
        attachments:
            attachments ??
            <AgentChatAttachment>[
              for (final attachment in draft.attachments)
                AgentChatAttachment(
                  type: attachment.kind == .image ? .localImage : .file,
                  path: attachment.path,
                  name: attachment.displayName,
                  attachmentId: attachment.attachmentId,
                  sizeBytes: attachment.sizeBytes,
                  localSourcePath: attachment.localSourcePath,
                ),
            ],
      );
}

/// Device-local drafts, including prompts awaiting runtime acceptance.
final class AgentChatComposerDrafts {
  AgentChatComposerDrafts({this._repository});

  static final Logger _logger = Logger('AgentChatComposerDrafts');
  static const Duration _saveDelay = Duration(milliseconds: 200);
  static const Duration _loadTimeout = Duration(seconds: 2);
  final AgentChatDraftRepository? _repository;
  final Map<AgentChatDraftKey, AgentChatComposerDraft> _drafts = {};
  final Map<AgentChatDraftKey, Map<String, AgentChatDraftSubmission>> _pending =
      {};
  final Map<AgentChatDraftKey, Set<String>> _settled = {};
  final Set<AgentChatDraftKey> _cleared = {};
  final Map<AgentChatDraftKey, Map<String, String>> _ids = {};
  final Map<AgentChatDraftKey, int> _revisions = {};
  final Map<AgentChatDraftKey, Future<AgentChatComposerDraft>> _loads = {};
  final Set<AgentChatDraftKey> _loadFailures = {};
  final Map<AgentChatDraftKey, Set<VoidCallback>> _listeners = {};
  final Set<AgentChatDraftKey> _dirty = {};
  Timer? _timer;
  Future<void>? _saving;

  AgentChatComposerDraft read(
    String chatId, {
    String hostId = 'local',
    String workspaceId = '',
  }) =>
      _drafts[_key(chatId, hostId, workspaceId)] ??
      AgentChatComposerDraft.empty;

  Future<AgentChatComposerDraft> hydrate(
    String chatId, {
    String hostId = 'local',
    String workspaceId = '',
  }) {
    final key = _key(chatId, hostId, workspaceId);
    final loading = _loads.putIfAbsent(
      key,
      () => _load(key).whenComplete(() {
        if (_loadFailures.contains(key)) _loads.remove(key);
      }),
    );
    return loading.then((_) => _drafts[key] ?? AgentChatComposerDraft.empty);
  }

  Future<AgentChatComposerDraft> _load(AgentChatDraftKey key) async {
    final revision = _revisions[key] ?? 0;
    try {
      final snapshot = await _repository?.load(key).timeout(_loadTimeout);
      if (snapshot != null && !_cleared.contains(key)) {
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
        final ids = _ids.putIfAbsent(key, () => {});
        for (final entry in Map<String, String>.from(
          decoded['ids'] as Map? ?? const {},
        ).entries) {
          if (!(_settled[key]?.contains(entry.value) ?? false)) {
            ids.putIfAbsent(entry.key, () => entry.value);
          }
        }
        _notify(key);
      }
      _loadFailures.remove(key);
    } on Object catch (error, stackTrace) {
      _loadFailures.add(key);
      _logger.warning('Could not restore chat draft.', error, stackTrace);
    }
    return _drafts[key] ?? .empty;
  }

  Future<void> ensureHydrated(
    String chatId, {
    String hostId = 'local',
    String workspaceId = '',
  }) async {
    await hydrate(chatId, hostId: hostId, workspaceId: workspaceId);
    if (_loadFailures.contains(_key(chatId, hostId, workspaceId))) {
      throw StateError('Chat drafts could not be read. Try again.');
    }
  }

  void write(
    String chatId,
    AgentChatComposerDraft draft, {
    String hostId = 'local',
    String workspaceId = '',
  }) {
    final key = _key(chatId, hostId, workspaceId);
    if (draft.isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = draft;
    }
    _changed(key);
  }

  String claimSubmissionId(
    String chatId,
    AgentChatComposerDraft draft,
    String Function() newId, {
    String hostId = 'local',
    String workspaceId = '',
  }) => _ids
      .putIfAbsent(_key(chatId, hostId, workspaceId), () => {})
      .putIfAbsent(draft.signature, newId);

  void beginSubmission(
    String chatId,
    String clientMessageId,
    AgentChatComposerDraft draft, {
    String hostId = 'local',
    String workspaceId = '',
    bool preserveComposer = true,
    String? model,
    String? reasoningEffort,
    AgentChatInteractionMode? interactionMode,
    AgentChatDelivery delivery = AgentChatDelivery.auto,
    DateTime? createdAt,
    List<AgentChatAttachment>? messageAttachments,
  }) {
    final key = _key(chatId, hostId, workspaceId);
    final current = _drafts[key];
    _ids.putIfAbsent(key, () => {})[draft.signature] = clientMessageId;
    final pending = _pending.putIfAbsent(key, () => {});
    if (!preserveComposer || !pending.containsKey(clientMessageId)) {
      pending[clientMessageId] = AgentChatDraftSubmission(
        clientMessageId: clientMessageId,
        draft: preserveComposer && current?.signature == draft.signature
            ? current!
            : draft,
        createdAt:
            createdAt ??
            pending[clientMessageId]?.createdAt ??
            DateTime.now().toUtc(),
        model: model,
        reasoningEffort: reasoningEffort,
        interactionMode: interactionMode,
        delivery: delivery,
        attachments: messageAttachments,
      );
    }
    _changed(key);
  }

  void settleSubmission(
    String chatId,
    String clientMessageId, {
    String hostId = 'local',
    String workspaceId = '',
  }) {
    final key = _key(chatId, hostId, workspaceId);
    _pending[key]?.remove(clientMessageId);
    _settled.putIfAbsent(key, () => {}).add(clientMessageId);
    _ids[key]?.removeWhere((_, id) => id == clientMessageId);
    _changed(key);
  }

  void remove(
    String chatId, {
    String hostId = 'local',
    String workspaceId = '',
  }) {
    final key = _key(chatId, hostId, workspaceId);
    _drafts.remove(key);
    _pending.remove(key);
    _ids.remove(key);
    _cleared.add(key);
    _changed(key);
  }

  List<AgentChatDraftSubmission> pending(
    String chatId, {
    String hostId = 'local',
    String workspaceId = '',
  }) => List<AgentChatDraftSubmission>.unmodifiableOf(
    _pending[_key(chatId, hostId, workspaceId)]?.values ?? const [],
  );

  void addListener(
    String chatId,
    VoidCallback listener, {
    String hostId = 'local',
    String workspaceId = '',
  }) => _listeners
      .putIfAbsent(_key(chatId, hostId, workspaceId), () => {})
      .add(listener);

  void removeListener(
    String chatId,
    VoidCallback listener, {
    String hostId = 'local',
    String workspaceId = '',
  }) {
    final key = _key(chatId, hostId, workspaceId);
    _listeners[key]?.remove(listener);
    if (_listeners[key]?.isEmpty ?? false) _listeners.remove(key);
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

  /// Drains the latest snapshots in order, including edits during a write.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    return _saving ??= _drain().whenComplete(() => _saving = null);
  }

  /// A send cannot leave the app until its retry identity is durable.
  Future<void> flushSubmission(
    String chatId, {
    String hostId = 'local',
    String workspaceId = '',
  }) async {
    await flush();
    if (_dirty.contains(_key(chatId, hostId, workspaceId))) {
      throw StateError('The message draft could not be saved. Try again.');
    }
  }

  Future<void> _drain() async {
    final failed = <AgentChatDraftKey>{};
    while (_dirty.any((key) => !failed.contains(key))) {
      final key = _dirty.firstWhere((key) => !failed.contains(key));
      await hydrate(
        key.chatId,
        hostId: key.hostId,
        workspaceId: key.workspaceId,
      );
      if (_loadFailures.contains(key) && !_cleared.contains(key)) {
        failed.add(key);
        continue;
      }
      _dirty.remove(key);
      final draft = _drafts[key] ?? AgentChatComposerDraft.empty;
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
              'ids': _ids[key] ?? const {},
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

  AgentChatDraftKey _key(String chatId, String hostId, String workspaceId) => (
    hostId: hostId.trim().isEmpty ? 'local' : hostId.trim(),
    workspaceId: workspaceId,
    chatId: chatId,
  );

  Map<String, Object?> _encodeDraft(AgentChatComposerDraft draft) => {
    'text': draft.text,
    'attachments': <Object>[
      for (final attachment in draft.attachments)
        {
          'id': attachment.id,
          'kind': attachment.kind.name,
          'path': attachment.path,
          'displayName': attachment.displayName,
          'localSourcePath': attachment.localSourcePath,
          'attachmentId': attachment.attachmentId,
          'sizeBytes': attachment.sizeBytes,
        },
    ],
  };

  AgentChatComposerDraft _decodeDraft(dynamic value) {
    final decoded = value as Map;
    return AgentChatComposerDraft(
      text: decoded['text'] as String,
      attachments: <TerminalComposerAttachment>[
        for (final attachment in decoded['attachments'] as List)
          TerminalComposerAttachment(
            id: attachment['id'] as String,
            kind: TerminalComposerAttachmentKind.values.byName(
              attachment['kind'] as String,
            ),
            path: attachment['path'] as String,
            displayName: attachment['displayName'] as String,
            localSourcePath: attachment['localSourcePath'] as String?,
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
