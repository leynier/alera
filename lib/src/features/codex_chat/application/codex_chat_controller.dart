import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/codex_chat/domain/codex_file_reference.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
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

@Riverpod(keepAlive: false)
RuntimeHostClient codexChatRuntimeClient(Ref ref) =>
    ref.watch(runtimeHostClientProvider);

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
  int _catalogueGeneration = 0;
  bool _recoveryPending = false;

  bool get _sessionTransitionInProgress => _sessionTransitionCount > 0;

  bool get canSteer =>
      !state.loading &&
      !state.interrupting &&
      state.recovery == null &&
      !_sessionTransitionInProgress &&
      state.snapshot.activeTurnId != null;

  @override
  CodexChatState build(String tabId) {
    _host = CodexChatHostClient(ref.watch(codexChatRuntimeClientProvider));
    _events = _host.events.listen(_onRuntimeEvent);
    ref.onDispose(() {
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

  Future<void> _load() async {
    try {
      final openFuture = _host.openThread(tabId);
      final open = await openFuture;
      if (!ref.mounted) return;
      _threadId = _string(open['threadId']);
      _threadGeneration += 1;
      final openSnapshot = CodexChatSnapshot.fromJson(open['snapshot']);
      final storedConfiguration = open['configuration'];
      state = _applyConfiguration(
        state.copyWith(
          loading: false,
          snapshot: openSnapshot,
          activeCwd: _string(open['cwd']),
          historyNextCursor: _string(open['historyNextCursor']),
          recovery: open['recovery'] == null
              ? null
              : CodexThreadRecovery.fromJson(open['recovery']),
          error: null,
        ),
        storedConfiguration,
      );
      _drainQueuedMessageIfIdle();
      await _refreshCapabilities();
      if (!ref.mounted) return;
      await _loadCatalogues();
      if (storedConfiguration == null) {
        _persistTabConfiguration();
      }
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(loading: false, error: _safeError(error));
    }
  }

  Future<void> _refreshCapabilities() async {
    final generation = ++_capabilityGeneration;
    var supportsSessions = await _host.supportsSessions();
    if (!supportsSessions) {
      supportsSessions = await _host.supportsSessions();
    }
    final supportsAutoReview = await _host.supportsTurnPolicy();
    if (!ref.mounted || generation != _capabilityGeneration) return;
    final permissionMode =
        !supportsAutoReview && state.permissionMode == 'auto-review'
        ? 'on-request'
        : state.permissionMode;
    final permissionChanged = permissionMode != state.permissionMode;
    state = state.copyWith(
      supportsSessions: supportsSessions,
      supportsAutoReview: supportsAutoReview,
      permissionMode: permissionMode,
    );
    if (permissionChanged) {
      _persistTabConfiguration();
    }
  }

  Future<void> retry() async {
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
          historyNextCursor: null,
          recovery: null,
          error: null,
        ),
        response['configuration'],
      );
      _drainQueuedMessageIfIdle();
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(error: _safeError(error));
    } finally {
      _recoveryPending = false;
    }
  }

  Future<void> send(
    String text, {
    List<CodexInputAttachment> attachments = const <CodexInputAttachment>[],
    List<CodexDraftItem> draftItems = const <CodexDraftItem>[],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty && draftItems.isEmpty) return;
    final message = CodexQueuedMessage(
      text: trimmed,
      attachments: List<CodexInputAttachment>.unmodifiable(attachments),
      draftItems: List<CodexDraftItem>.unmodifiable(draftItems),
      id: _newClientMessageId(),
    );
    if (state.loading ||
        state.recovery != null ||
        state.busy ||
        _sessionTransitionInProgress) {
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
        expectedThreadId: _threadId,
        userMessage: _userMessagePresentation(message),
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

  void _drainQueuedMessageIfIdle() {
    if (!ref.mounted ||
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

  Future<bool> steer(
    String text, {
    List<CodexInputAttachment> attachments = const <CodexInputAttachment>[],
    List<CodexDraftItem> draftItems = const <CodexDraftItem>[],
  }) async {
    final turnId = state.snapshot.activeTurnId;
    if (!canSteer ||
        turnId == null ||
        (text.trim().isEmpty && attachments.isEmpty && draftItems.isEmpty)) {
      return false;
    }
    try {
      final message = CodexQueuedMessage(
        text: text.trim(),
        attachments: attachments,
        draftItems: draftItems,
      );
      await _host.steer(
        tabId,
        turnId,
        _buildInput(message, state),
        userMessage: _userMessagePresentation(message),
        clientUserMessageId: _newClientMessageId(),
      );
      return true;
    } catch (error) {
      state = state.copyWith(error: _safeError(error));
      return false;
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

  Future<void> implementPlan() async {
    state = state.copyWith(planMode: false, collaborationMode: null);
    _persistConfiguration();
    await send('Implement plan');
  }

  /// Local plan fallback used when an older app-server does not send its own
  /// implement-plan question. Keep the actions as ordinary user turns so the
  /// server remains the source of truth for plan execution.
  Future<void> declinePlan() async {
    state = state.copyWith(planMode: false, collaborationMode: null);
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
    if (normalized == null || normalized.isEmpty) return;
    state = state.copyWith(
      collaborationMode: normalized,
      planMode: normalized == 'plan',
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
