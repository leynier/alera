import 'dart:async';
import 'codex_composer_draft_store.dart';
import 'dart:convert';
import 'package:alera/src/features/codex_chat/domain/codex_queue_message.dart';

import 'package:alera/src/features/codex_chat/domain/codex_file_reference.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline_identity.dart';
import 'package:alera/src/features/codex_chat/infra/codex_chat_host_client.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'codex_chat_controller.g.dart';
part 'codex_chat_controller_helpers.dart';
part 'codex_chat_controller_sessions.dart';
part 'codex_chat_controller_catalogues.dart';
part 'codex_chat_controller_request_responses.dart';
part 'codex_chat_controller_events.dart';
part 'codex_chat_controller_lifecycle.dart';
part 'codex_chat_controller_goals.dart';
part 'codex_chat_controller_shared_queue.dart';
part 'codex_chat_controller_delivery.dart';
part 'codex_chat_controller_capabilities.dart';

@Riverpod(keepAlive: false)
RuntimeHostClient codexChatRuntimeClient(Ref ref) =>
    ref.watch(runtimeHostClientProvider);

@Riverpod(keepAlive: true)
CodexChatHostClient codexChatHostClient(Ref ref) {
  final host = CodexChatHostClient(ref.watch(codexChatRuntimeClientProvider));
  ref.onDispose(host.dispose);
  return host;
}

@Riverpod(keepAlive: false)
class CodexChatController extends _$CodexChatController {
  late final CodexChatHostClient _host;
  StreamSubscription<RuntimeHostEvent>? _events;
  Timer? _interruptSafetyTimer;
  bool _historyLoading = false;
  int _sessionTransitionCount = 0;
  List<CodexQueuedMessage> _suspendedSessionQueue =
      const <CodexQueuedMessage>[];
  bool _sessionTransitionSucceeded = false;
  String? _threadId;
  int _threadGeneration = 0;
  int _capabilityGeneration = 0;
  Future<void>? _reconnectRefresh;
  bool _capabilityRefreshBlocked = false;
  bool _transferringLegacyQueue = false;
  int _catalogueGeneration = 0;
  bool _goalCapabilityAdvertised = false;
  bool _goalsAvailable = true;
  bool _recoveryPending = false;
  final List<RuntimeHostEvent> _deferredThreadEvents = <RuntimeHostEvent>[];
  bool _opening = false;
  Completer<bool>? _openingResult;
  int _loadGeneration = 0;
  bool _steering = false;

  bool get _sessionTransitionInProgress => _sessionTransitionCount > 0;

  String? get threadId => _threadId;

  bool get canSteer =>
      _reconnectRefresh == null &&
      !_capabilityRefreshBlocked &&
      !state.sharedQueueUnavailable &&
      !_steering &&
      !state.loading &&
      !state.interrupting &&
      !state.historyLocked &&
      state.recovery == null &&
      !_sessionTransitionInProgress &&
      state.snapshot.activeTurnId != null;

  @override
  CodexChatState build(String tabId) {
    _draftStore = ref.read(codexComposerDraftStoreProvider);
    _host = ref.watch(codexChatHostClientProvider);
    _events = _host.events.listen(_onRuntimeEvent);
    ref.onDispose(() {
      final opening = _openingResult;
      if (opening != null && !opening.isCompleted) opening.complete(false);
      _interruptSafetyTimer?.cancel();
      _events?.cancel();
    });
    unawaited(_load());
    final defaults = ref.read(settingsControllerProvider).codexChat;
    return CodexChatState(
      selectedModel: defaults.selectedModel,
      reasoningEffort: defaults.reasoningEffort,
      speedMode: defaults.speedMode,
      permissionMode: _supportedPermissionMode(defaults.permissionMode),
      planMode: defaults.planMode,
      collaborationMode: defaults.planMode ? 'plan' : null,
    );
  }

  Future<void> retry() async {
    if (_capabilityRefreshBlocked) {
      await _refreshCapabilitiesAndGoal();
      return;
    }
    _threadGeneration += 1;
    state = state.copyWith(loading: true, error: null);
    await _load();
  }

  Future<void> recoverThread() async {
    if (_recoveryPending || state.recovery == null) return;
    final expectedThreadId = _threadId;
    if (expectedThreadId == null) {
      state = state.copyWith(
        error:
            'The Codex conversation changed before recovery. Review the current conversation and try again.',
      );
      return;
    }
    _recoveryPending = true;
    try {
      final response = await _host.recoverThread(
        tabId,
        expectedThreadId: expectedThreadId,
      );
      if (!ref.mounted) return;
      _threadId = _string(response['threadId']);
      _threadGeneration += 1;
      state = _applyConfiguration(
        state.copyWith(
          snapshot: CodexChatSnapshot.fromJson(response['snapshot']),
          chatFeatures:
              (response['chatFeatures'] as List?)
                  ?.whereType<String>()
                  .toSet() ??
              state.chatFeatures,
          historyRevision: response['historyRevision'] as int? ?? 0,
          queueState: const {},
          queuedMessages: state.supportsSharedQueue
              ? const []
              : state.queuedMessages,
          activeCwd: _string(response['cwd']) ?? state.activeCwd,
          historyNextCursor: null,
          recovery: null,
          error: null,
        ),
        response['configuration'],
      );
      if (response['queue'] is Map) {
        _applyQueueSnapshot(
          Map<String, Object?>.from(response['queue']! as Map),
        );
      }
      _drainQueuedMessageIfIdle();
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(error: _safeError(error));
    } finally {
      _recoveryPending = false;
    }
  }

  late CodexComposerDraftStore _draftStore;
  Map<String, String> get _pendingSubmissionIds =>
      _draftStore.submissionIdsFor(tabId, _threadId);

  Future<bool> send(
    String text, {
    List<CodexInputAttachment> attachments = const <CodexInputAttachment>[],
    List<CodexDraftItem> draftItems = const <CodexDraftItem>[],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty && draftItems.isEmpty) {
      return false;
    }
    final message = CodexQueuedMessage(
      text: trimmed,
      attachments: List<CodexInputAttachment>.unmodifiable(attachments),
      draftItems: List<CodexDraftItem>.unmodifiable(draftItems),
      id: _newClientMessageId(),
    );
    if (state.loading) {
      final opening = _openingResult;
      if (opening == null ||
          !await opening.future ||
          !ref.mounted ||
          state.loading) {
        return false;
      }
    }
    if (!await _awaitRuntimeCapabilities() || state.historyOutdated) {
      return false;
    }
    if (!state.supportsSharedQueue &&
        (state.loading ||
            state.queuePaused ||
            state.recovery != null ||
            state.busy ||
            _sessionTransitionInProgress)) {
      state = state.copyWith(
        queuedMessages: <CodexQueuedMessage>[...state.queuedMessages, message],
      );
      return true;
    }
    final attempts = _draftStore.messageAttemptsFor(tabId, _threadId);
    final signature = jsonEncode(codexQueueDraft(message));
    final id = attempts.claim(signature, message.id!);
    var accepted = false;
    try {
      accepted = await _sendNow(
        CodexQueuedMessage(
          id: id,
          text: message.text,
          attachments: message.attachments,
          draftItems: message.draftItems,
        ),
      );
      return accepted;
    } finally {
      if (!accepted) attempts.retainForRetry(signature, id);
    }
  }

  void _drainQueuedMessageIfIdle() {
    if (!ref.mounted ||
        _reconnectRefresh != null ||
        _capabilityRefreshBlocked ||
        state.sharedQueueUnavailable ||
        state.supportsSharedQueue ||
        state.queuePaused ||
        state.loading ||
        state.recovery != null ||
        state.busy ||
        _sessionTransitionInProgress ||
        state.queuedMessages.isEmpty) {
      return;
    }
    final nextMessage = state.queuedMessages.first;
    state = state.copyWith(
      queuedMessages: state.queuedMessages.skip(1).toList(growable: false),
    );
    unawaited(_sendNow(nextMessage));
  }

  Future<void> stop() async {
    final generation = _threadGeneration;
    final threadId = _threadId;
    final turnId = state.snapshot.activeTurnId;
    final shared = state.supportsSharedQueue;
    if (state.interrupting) return;
    if (!shared) {
      state = state.copyWith(queueState: {...state.queueState, 'paused': true});
    }
    if ((!shared || turnId == null) &&
        !state.sharedQueueUnavailable &&
        _reconnectRefresh == null &&
        !_capabilityRefreshBlocked &&
        !await queueAction('pause')) {
      return;
    }
    if (!ref.mounted ||
        generation != _threadGeneration ||
        turnId == null ||
        state.interrupting) {
      return;
    }
    state = state.copyWith(interrupting: true, error: null);
    _interruptSafetyTimer?.cancel();
    _interruptSafetyTimer = Timer(const Duration(seconds: 2), () {
      if (!ref.mounted) return;
      state = state.copyWith(interrupting: false, sending: false);
    });
    try {
      await _host.request('codex.turn.interrupt', {
        'tabId': tabId,
        'turnId': turnId,
        'expectedThreadId': threadId,
      });
    } catch (error) {
      _interruptSafetyTimer?.cancel();
      if (ref.mounted) {
        state = state.copyWith(interrupting: false, error: _safeError(error));
      }
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
    String? commitTitle,
    String? delivery,
  }) async {
    try {
      await _host.review(
        tabId,
        target: target,
        argument: argument,
        commitTitle: commitTitle,
        delivery: delivery,
      );
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
    }
  }

  Future<void> implementPlan() async {
    state = state.copyWith(planMode: false, collaborationMode: null);
    _persistConfiguration();
    await send('Implement plan');
  }

  /// Local plan fallback used when an older app-server does not send its own
  /// implement-plan question. Keep the actions as ordinary user turns so the
  /// server remains the source of truth for plan execution.
  Future<void> declinePlan() async {
    state = state.copyWith(planMode: true, collaborationMode: 'plan');
    _persistConfiguration();
    await send('Do not implement the plan.');
  }

  Future<void> refinePlan(String refinement) async {
    final text = refinement.trim();
    if (text.isEmpty) return;
    state = state.copyWith(planMode: true, collaborationMode: 'plan');
    _persistConfiguration();
    await send(text);
  }

  void setModel(String? model) {
    if (model == null || model.isEmpty) return;
    final option = state.models.where((item) => item.id == model).firstOrNull;
    state = state.copyWith(
      selectedModel: model,
      reasoningEffort: _supportedEffort(option, state.reasoningEffort),
      speedMode: option?.supportsFastMode == false ? 'normal' : state.speedMode,
    );
    _persistConfiguration();
  }

  void setReasoning(String effort) {
    state = state.copyWith(
      reasoningEffort: _supportedEffort(state.selectedModelOption, effort),
    );
    _persistConfiguration();
  }

  void setPermissionMode(String mode) {
    final permissionMode = mode == 'auto-review' && !state.supportsAutoReview
        ? 'on-request'
        : _supportedPermissionMode(mode);
    state = state.copyWith(permissionMode: permissionMode);
    _persistConfiguration();
  }

  void setSpeed(String mode) {
    state = state.copyWith(
      speedMode:
          mode == 'fast' && state.selectedModelOption?.supportsFastMode == false
          ? 'normal'
          : mode,
    );
    _persistConfiguration();
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
    _persistConfiguration();
  }

  void setCollaborationMode(String? mode) {
    final normalized = mode?.trim();
    final nextMode = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    state = state.copyWith(
      collaborationMode: nextMode,
      planMode: nextMode == 'plan',
    );
    _persistConfiguration();
  }

  void _persistConfiguration() {
    _persistTabConfiguration();
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .updateCodexChat(
            CodexChatSettings(
              selectedModel: state.selectedModel,
              reasoningEffort: state.reasoningEffort,
              speedMode: state.speedMode,
              permissionMode: state.permissionMode,
              planMode: state.planMode,
            ),
          )
          .catchError((_) {}),
    );
  }

  void _persistTabConfiguration() {
    unawaited(
      _host
          .configureTab(tabId, _configurationPayload(state))
          .catchError((_) => <String, Object?>{}),
    );
  }

  void removeQueuedMessage(int index) {
    if (state.supportsSharedQueue) {
      if (index >= 0 && index < state.queuedMessages.length) {
        unawaited(
          queueAction('remove', messageId: state.queuedMessages[index].id),
        );
      }
      return;
    }
    if (index < 0 || index >= state.queuedMessages.length) return;
    final next = <CodexQueuedMessage>[...state.queuedMessages]..removeAt(index);
    state = state.copyWith(queuedMessages: next);
  }

  void editQueuedMessage(
    int index, {
    required String text,
    List<CodexInputAttachment> attachments = const <CodexInputAttachment>[],
    List<CodexDraftItem> draftItems = const <CodexDraftItem>[],
  }) {
    if (index < 0 || index >= state.queuedMessages.length) return;
    final next = <CodexQueuedMessage>[...state.queuedMessages];
    next[index] = CodexQueuedMessage(
      id: next[index].id,
      text: text.trim(),
      attachments: List<CodexInputAttachment>.unmodifiable(attachments),
      draftItems: List<CodexDraftItem>.unmodifiable(draftItems),
    );
    if (next[index].text.isEmpty &&
        next[index].attachments.isEmpty &&
        next[index].draftItems.isEmpty) {
      next.removeAt(index);
    }
    state = state.copyWith(queuedMessages: next);
  }

  void clearQueuedMessages() {
    state = state.copyWith(queuedMessages: const <CodexQueuedMessage>[]);
  }

  void _recordRequestError(Object error) {
    state = state.copyWith(error: _safeError(error));
  }
}
