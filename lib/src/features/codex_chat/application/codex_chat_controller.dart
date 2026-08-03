import 'dart:async';

import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/infra/codex_chat_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'codex_chat_controller.g.dart';
part 'codex_chat_controller_helpers.dart';

@Riverpod(keepAlive: false)
RuntimeHostClient codexChatRuntimeClient(Ref ref) =>
    ref.watch(runtimeHostClientProvider);

@Riverpod(keepAlive: false)
class CodexChatController extends _$CodexChatController {
  late final CodexChatHostClient _host;
  StreamSubscription<RuntimeHostEvent>? _events;
  Timer? _interruptSafetyTimer;

  @override
  CodexChatState build(String tabId) {
    _host = CodexChatHostClient(ref.watch(codexChatRuntimeClientProvider));
    _events = _host.events.listen(_onRuntimeEvent);
    ref.onDispose(() {
      _interruptSafetyTimer?.cancel();
      _events?.cancel();
    });
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
      skills = _items(await _host.listSkills(tabId));
    } catch (_) {
      // Skills are optional on older app-server builds.
    }
    try {
      apps = _items(await _host.listApps(tabId));
    } catch (_) {
      // Apps are optional on older app-server builds.
    }
    if (!ref.mounted) return;
    final selectedModel =
        state.selectedModel ??
        (models.where((model) => model.isDefault).firstOrNull ??
                (models.isNotEmpty ? models.first : null))
            ?.id;
    final selectedOption = models
        .where((model) => model.id == selectedModel)
        .firstOrNull;
    final initialReasoning =
        selectedOption?.defaultReasoningEffort ?? state.reasoningEffort;
    state = state.copyWith(
      models: models,
      collaborationModes: modes,
      skills: skills,
      apps: apps,
      selectedModel: selectedModel,
      reasoningEffort: _supportedEffort(selectedOption, initialReasoning),
      speedMode: selectedOption?.supportsFastMode == false
          ? 'normal'
          : state.speedMode,
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
      id: _newClientMessageId(),
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
        collaborationMode: state.collaborationMode,
        clientUserMessageId: message.id,
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
    _interruptSafetyTimer?.cancel();
    _interruptSafetyTimer = Timer(const Duration(seconds: 2), () {
      if (!ref.mounted) return;
      state = state.copyWith(interrupting: false, sending: false);
    });
    try {
      await _host.interrupt(tabId, state.snapshot.activeTurnId);
    } catch (error) {
      _interruptSafetyTimer?.cancel();
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
      ], clientUserMessageId: _newClientMessageId());
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

  Future<void> startReview({
    String target = 'uncommittedChanges',
    String? argument,
    String? delivery,
  }) async {
    try {
      await _host.review(
        tabId,
        target: target,
        argument: argument,
        delivery: delivery,
      );
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> implementPlan() => send('Implement the plan.');

  /// Local plan fallback used when an older app-server does not send its own
  /// implement-plan question. Keep the actions as ordinary user turns so the
  /// server remains the source of truth for plan execution.
  Future<void> declinePlan() => send('Do not implement the plan.');

  Future<void> refinePlan(String refinement) {
    final text = refinement.trim();
    return text.isEmpty ? Future<void>.value() : send(text);
  }

  Future<void> respondApproval(
    CodexPendingRequest request, {
    required bool accepted,
    bool forSession = false,
  }) async {
    try {
      final result = request.isPermissionsRequest
          ? <String, Object?>{
              'permissions': accepted
                  ? _permissionSubset(request.params['permissions'])
                  : const <String, Object?>{},
              'scope': forSession ? 'session' : 'turn',
            }
          : <String, Object?>{
              'decision': accepted
                  ? forSession
                        ? 'acceptForSession'
                        : 'accept'
                  : 'decline',
            };
      await _host.respond(request.id, result: result);
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
        result: <String, Object?>{
          'answers': <String, Object?>{
            for (final entry in answers.entries)
              entry.key: <String, Object?>{'answers': entry.value},
          },
        },
      );
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> respondElicitation(
    CodexPendingRequest request, {
    required String action,
    Map<String, Object?> content = const <String, Object?>{},
  }) async {
    try {
      await _host.respond(
        request.id,
        result: <String, Object?>{
          'action': action,
          if (action == 'accept') 'content': content,
        },
      );
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> rejectRequest(CodexPendingRequest request) async {
    try {
      await _host.respond(
        request.id,
        error: <String, Object?>{
          'code': -32601,
          'message': 'Alera does not support this Codex request.',
        },
      );
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> submitQuestions(
    CodexPendingRequest request,
    Map<String, List<String>> answers,
  ) async {
    await respondQuestion(request, <String, Object?>{
      for (final entry in answers.entries) entry.key: entry.value,
    });
  }

  void setModel(String? model) {
    if (model == null || model.isEmpty) return;
    final option = state.models.where((item) => item.id == model).firstOrNull;
    state = state.copyWith(
      selectedModel: model,
      reasoningEffort: _supportedEffort(
        option,
        option?.defaultReasoningEffort ?? state.reasoningEffort,
      ),
      speedMode: option?.supportsFastMode == false ? 'normal' : state.speedMode,
    );
  }

  void setReasoning(String effort) {
    state = state.copyWith(
      reasoningEffort: _supportedEffort(state.selectedModelOption, effort),
    );
  }

  void setPermissionMode(String mode) {
    state = state.copyWith(permissionMode: mode);
  }

  void setSpeed(String mode) {
    state = state.copyWith(
      speedMode:
          mode == 'fast' && state.selectedModelOption?.supportsFastMode == false
          ? 'normal'
          : mode,
    );
  }

  void setPlanMode(bool enabled) {
    state = state.copyWith(
      planMode: enabled,
      collaborationMode: enabled
          ? 'plan'
          : state.collaborationMode == 'plan'
          ? null
          : state.collaborationMode,
    );
  }

  void setCollaborationMode(String? mode) {
    final normalized = mode?.trim();
    if (normalized == null || normalized.isEmpty) return;
    state = state.copyWith(
      collaborationMode: normalized,
      planMode: normalized == 'plan',
    );
  }

  void removeQueuedMessage(int index) {
    if (index < 0 || index >= state.queuedMessages.length) return;
    final next = <CodexQueuedMessage>[...state.queuedMessages]..removeAt(index);
    state = state.copyWith(queuedMessages: next);
  }

  void editQueuedMessage(
    int index, {
    required String text,
    List<CodexInputAttachment> attachments = const <CodexInputAttachment>[],
  }) {
    if (index < 0 || index >= state.queuedMessages.length) return;
    final next = <CodexQueuedMessage>[...state.queuedMessages];
    next[index] = CodexQueuedMessage(
      id: next[index].id,
      text: text.trim(),
      attachments: List<CodexInputAttachment>.unmodifiable(attachments),
    );
    if (next[index].text.isEmpty && next[index].attachments.isEmpty) {
      next.removeAt(index);
    }
    state = state.copyWith(queuedMessages: next);
  }

  void clearQueuedMessages() {
    state = state.copyWith(queuedMessages: const <CodexQueuedMessage>[]);
  }

  void _onRuntimeEvent(RuntimeHostEvent event) {
    if (event.name == 'codexServerChanged') {
      if (!ref.mounted) return;
      final status = event.payload['status']?.toString();
      if (status == 'error') {
        state = state.copyWith(
          error: _safeError(event.payload['error'] ?? 'Codex server failed.'),
        );
      }
      return;
    }
    if (event.name != 'codexThreadChanged') return;
    if (event.payload['tabId'] != tabId) return;
    final snapshot = event.payload['snapshot'];
    if (snapshot is! Map) return;
    final next = CodexChatSnapshot.fromJson(snapshot);
    if (!ref.mounted) return;
    if (!next.isBusy) _interruptSafetyTimer?.cancel();
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
