import 'dart:async';

import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/infra/codex_chat_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'codex_chat_controller.g.dart';

@Riverpod(keepAlive: false)
class CodexChatController extends _$CodexChatController {
  late final CodexChatHostClient _host;
  StreamSubscription<RuntimeHostEvent>? _events;

  @override
  CodexChatState build(String tabId) {
    _host = CodexChatHostClient(ref.watch(runtimeHostClientProvider));
    _events = _host.events.listen(_onRuntimeEvent);
    ref.onDispose(() => _events?.cancel());
    unawaited(_load());
    return const CodexChatState();
  }

  Future<void> _load() async {
    try {
      final open = await _host.openThread(tabId);
      if (!ref.mounted) return;
      final openSnapshot = CodexChatSnapshot.fromJson(open['snapshot']);
      state = state.copyWith(
        loading: false,
        snapshot: openSnapshot,
        selectedModel: _string(open['model']),
        error: null,
      );
      await _loadCatalogues();
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: _safeError(error));
    }
  }

  Future<void> retry() async {
    state = state.copyWith(loading: true, error: null);
    await _load();
  }

  Future<void> _loadCatalogues() async {
    final models = await _loadModels();
    List<Map<String, Object?>> modes = const <Map<String, Object?>>[];
    List<Map<String, Object?>> skills = const <Map<String, Object?>>[];
    List<Map<String, Object?>> apps = const <Map<String, Object?>>[];
    try {
      final payload = await _host.listCollaborationModes();
      modes = _items(payload);
    } catch (_) {
      // Collaboration modes are optional on older app-server builds.
    }
    try {
      skills = _items(await _host.listSkills());
    } catch (_) {
      // Skills are optional on older app-server builds.
    }
    try {
      apps = _items(await _host.listApps());
    } catch (_) {
      // Apps are optional on older app-server builds.
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      models: models,
      collaborationModes: modes,
      skills: skills,
      apps: apps,
    );
  }

  Future<List<CodexModelOption>> _loadModels() async {
    try {
      final payload = await _host.listModels();
      final items = _items(payload);
      final models = <CodexModelOption>[
        for (final item in items) CodexModelOption.fromJson(item),
      ];
      if (models.isNotEmpty) return models;
    } catch (_) {
      // Fall back below. The fallback is intentionally a current Codex set,
      // never a persisted model snapshot from an older app.
    }
    return const <CodexModelOption>[
      CodexModelOption(id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol'),
    ];
  }

  Future<void> send(
    String text, {
    List<CodexInputAttachment> attachments = const <CodexInputAttachment>[],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    final message = CodexQueuedMessage(
      text: trimmed,
      attachments: List<CodexInputAttachment>.unmodifiable(attachments),
    );
    if (state.busy) {
      state = state.copyWith(
        queuedMessages: <CodexQueuedMessage>[...state.queuedMessages, message],
      );
      return;
    }
    await _sendNow(message);
  }

  Future<void> _sendNow(CodexQueuedMessage message) async {
    state = state.copyWith(sending: true, error: null);
    try {
      await _host.startTurn(
        tabId,
        _buildInput(message, state),
        model: state.selectedModel,
        reasoningEffort: state.reasoningEffort,
        speedMode: state.speedMode,
        permissionMode: state.permissionMode,
        planMode: state.planMode,
      );
      if (ref.mounted) {
        state = state.copyWith(sending: false);
      }
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(sending: false, error: _safeError(error));
      }
    }
  }

  Future<void> stop() async {
    if (state.snapshot.activeTurnId == null || state.interrupting) return;
    state = state.copyWith(interrupting: true, error: null);
    try {
      await _host.interrupt(tabId, state.snapshot.activeTurnId);
      if (ref.mounted) {
        state = state.copyWith(interrupting: false, sending: false);
      }
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(interrupting: false, error: _safeError(error));
      }
    }
  }

  Future<void> steer(String text) async {
    final turnId = state.snapshot.activeTurnId;
    if (turnId == null || text.trim().isEmpty) return;
    try {
      await _host.steer(tabId, turnId, <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': text.trim()},
      ]);
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> rename(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      await _host.rename(tabId, trimmed);
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> compact() async {
    try {
      await _host.compact(tabId);
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> startReview() async {
    try {
      await _host.review(tabId);
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> implementPlan() => send('Implement the plan.');

  Future<void> respondApproval(
    CodexPendingRequest request, {
    required bool accepted,
    bool forSession = false,
  }) async {
    try {
      await _host.respond(
        request.id,
        result: <String, Object?>{
          'decision': accepted
              ? (forSession ? 'acceptForSession' : 'accept')
              : 'decline',
        },
      );
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> respondQuestion(
    CodexPendingRequest request,
    Map<String, Object?> answers,
  ) async {
    try {
      await _host.respond(
        request.id,
        result: <String, Object?>{'answers': answers},
      );
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  void setModel(String? model) {
    if (model == null || model.isEmpty) return;
    state = state.copyWith(selectedModel: model);
  }

  void setReasoning(String effort) {
    state = state.copyWith(reasoningEffort: effort);
  }

  void setPermissionMode(String mode) {
    state = state.copyWith(permissionMode: mode);
  }

  void setSpeed(String mode) {
    state = state.copyWith(speedMode: mode);
  }

  void setPlanMode(bool enabled) {
    state = state.copyWith(planMode: enabled);
  }

  void removeQueuedMessage(int index) {
    if (index < 0 || index >= state.queuedMessages.length) return;
    final next = <CodexQueuedMessage>[...state.queuedMessages]..removeAt(index);
    state = state.copyWith(queuedMessages: next);
  }

  void _onRuntimeEvent(RuntimeHostEvent event) {
    if (event.name != 'codexThreadChanged') return;
    if (event.payload['tabId'] != tabId) return;
    final snapshot = event.payload['snapshot'];
    if (snapshot is! Map) return;
    final next = CodexChatSnapshot.fromJson(snapshot);
    if (!ref.mounted) return;
    state = state.copyWith(
      snapshot: next,
      sending: next.isBusy ? state.sending : false,
      interrupting: next.isBusy ? state.interrupting : false,
      error: null,
    );
    if (!next.isBusy && state.queuedMessages.isNotEmpty) {
      final nextMessage = state.queuedMessages.first;
      state = state.copyWith(
        queuedMessages: state.queuedMessages.skip(1).toList(growable: false),
      );
      unawaited(_sendNow(nextMessage));
    }
  }
}

List<Map<String, Object?>> _items(Map<String, Object?> payload) {
  final value = payload['data'] ?? payload['items'] ?? payload['apps'];
  if (value is! List) return const <Map<String, Object?>>[];
  return <Map<String, Object?>>[
    for (final item in value)
      if (item is Map) Map<String, Object?>.from(item),
  ];
}

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

String _safeError(Object error) {
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  return message.isEmpty ? 'Codex request failed.' : message;
}

List<Map<String, Object?>> _buildInput(
  CodexQueuedMessage message,
  CodexChatState state,
) {
  final skill = _skillInput(message.text, state.skills);
  return <Map<String, Object?>>[
    if (skill != null) skill.$1,
    if (message.text.isNotEmpty && skill == null)
      <String, Object?>{'type': 'text', 'text': message.text},
    if (skill != null && skill.$2.isNotEmpty)
      <String, Object?>{'type': 'text', 'text': skill.$2},
    for (final attachment in message.attachments)
      if (attachment.isImage)
        <String, Object?>{'type': 'localImage', 'path': attachment.path}
      else
        <String, Object?>{
          'type': 'text',
          'text': 'Attached file: ${attachment.path}',
        },
  ];
}

(Map<String, Object?>, String)? _skillInput(
  String text,
  List<Map<String, Object?>> skills,
) {
  final match = RegExp(
    r'^/skill\s+([^\s]+)(?:\s+(.+))?$',
    dotAll: true,
  ).firstMatch(text);
  if (match == null) return null;
  final name = match.group(1)!;
  for (final skill in skills) {
    final skillName = skill['name']?.toString();
    final path = skill['path']?.toString();
    if (skillName == name && path != null && path.isNotEmpty) {
      return (
        <String, Object?>{'type': 'skill', 'name': skillName, 'path': path},
        match.group(2)?.trim() ?? '',
      );
    }
  }
  return null;
}
