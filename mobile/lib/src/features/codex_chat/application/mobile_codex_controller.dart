import 'dart:async';

import 'mobile_codex_composer_draft_store.dart';

import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_catalog_selection.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_file_reference.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_preferences.dart';
import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_preferences_repository.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_codex_controller.g.dart';
part 'mobile_codex_controller_configuration_helpers.dart';
part 'mobile_codex_controller_helpers.dart';
part 'mobile_codex_controller_identity.dart';
part 'mobile_codex_controller_lifecycle.dart';
part 'mobile_codex_controller_workspace.dart';
part 'mobile_codex_controller_options.dart';
part 'mobile_codex_controller_review.dart';
part 'mobile_codex_controller_sessions.dart';
part 'mobile_codex_controller_catalogues.dart';
part 'mobile_codex_controller_goals.dart';
part 'mobile_codex_controller_capabilities.dart';
part 'mobile_codex_controller_shared_queue.dart';
part 'mobile_codex_controller_delivery.dart';

@riverpod
Future<MobileCodexClient> mobileCodexClient(Ref ref, String hostId) =>
    watchHostConnection(ref, hostId);

@riverpod
class MobileCodexController extends _$MobileCodexController
    with _MobileCodexControllerLifecycle {
  @override
  final Logger _logger = Logger('MobileCodexController');
  @override
  MobileCodexClient? _client;
  StreamSubscription<MobileRuntimeEvent>? _events;
  Timer? _interruptSafetyTimer;
  @override
  final List<MobileRuntimeEvent> _deferredThreadEvents = <MobileRuntimeEvent>[];
  @override
  Timer? _deferredThreadEventTimer;
  bool _historyLoading = false;
  int _sessionTransitionCount = 0;
  List<Map<String, Object?>> _suspendedSessionQueue =
      const <Map<String, Object?>>[];
  bool _sessionTransitionSucceeded = false;
  @override
  String? _threadId;
  @override
  int _threadGeneration = 0;
  int _accountCatalogueRevision = 0;
  bool _accountCatalogueRefreshPending = false;
  bool _accountCatalogueBuildAwaitingPublication = false;
  bool _goalsAvailable = true;
  bool _goalRefreshPending = false;

  @override
  bool get _sessionTransitionInProgress => _sessionTransitionCount > 0;

  @override
  Timer? get _interruptSafetyTimerValue => _interruptSafetyTimer;

  @override
  Future<void> _reloadCatalogue(String catalog) =>
      _reloadMobileCodexCatalogue(catalog);

  @override
  Future<void> _retryGoalAvailability() => _refreshGoalAvailability();

  @override
  Future<void> _refreshSharedQueue() => refreshQueue();

  @override
  Future<MobileCodexState> build(String hostId, String tabId) async {
    _draftStore = ref.read(mobileCodexComposerDraftStoreProvider);
    _accountCatalogueBuildAwaitingPublication = true;
    _registerAccountCatalogueReplay();
    final client = await ref.watch(mobileCodexClientProvider(hostId).future);
    if (!client.supportsCodexChat) {
      throw UnsupportedError('This runtime host does not support Codex chat.');
    }
    _client = client;
    _events = client.events.listen(_onEvent);
    ref.onDispose(() {
      _interruptSafetyTimer?.cancel();
      _deferredThreadEventTimer?.cancel();
      _events?.cancel();
    });
    final response = await client.codexRequest(
      'codex.thread.open',
      <String, Object?>{'tabId': tabId, 'supportsMissingRolloutRecovery': true},
    );
    final storedConfiguration = response['configuration'];
    _threadId = _string(response['threadId']);
    _threadGeneration += 1;
    var next = MobileCodexState.fromSnapshot(response['snapshot']).copyWith(
      chatFeatures:
          (response['chatFeatures'] as List?)?.whereType<String>().toSet() ??
          const {},
      historyRevision: response['historyRevision'] as int? ?? 0,
      activeCwd: _string(response['cwd']),
      historyNextCursor: _string(response['historyNextCursor']),
      recovery: response['recovery'] == null
          ? null
          : MobileCodexThreadRecovery.fromJson(response['recovery']),
    );
    if (next.supportsSharedQueue && response['queue'] is Map) {
      next = _withSharedQueue(
        next,
        Map<String, Object?>.from(response['queue']! as Map),
      );
    }
    next = await _loadInitialGoal(client, next);
    next = _applyMobileConfiguration(next, storedConfiguration);
    final initialCatalogues = await _loadInitialCatalogues(client, next);
    next = initialCatalogues.state;
    final initializedAccountRevision = initialCatalogues.revision;
    if (storedConfiguration == null) {
      try {
        final preferences = await ref
            .read(mobileCodexPreferencesRepositoryProvider)
            .load(hostId);
        final preferredModel =
            next.models.any((model) => model.id == preferences.model)
            ? preferences.model
            : next.selectedModel;
        final preferredOption = next.models
            .where((model) => model.id == preferredModel)
            .firstOrNull;
        next = next.copyWith(
          selectedModel: preferredModel,
          reasoningEffort: _supportedEffort(
            preferredOption,
            preferences.reasoningEffort,
          ),
          speedMode:
              preferences.speedMode == 'fast' &&
                  preferredOption?.supportsFastMode == true
              ? 'fast'
              : 'normal',
          permissionMode: preferences.permissionMode,
          planMode: preferences.planMode,
          collaborationMode: preferences.planMode ? 'plan' : null,
        );
        await client.codexRequest('codex.tab.configure', <String, Object?>{
          'tabId': tabId,
          'configuration': _mobileConfigurationPayload(next),
        });
      } catch (error, stackTrace) {
        _logger.warning(
          'Codex preferences were unavailable.',
          error,
          stackTrace,
        );
      }
    }
    final pendingCatalogues = await _loadPendingAccountCatalogues(
      client,
      next,
      initializedAccountRevision,
    );
    next = pendingCatalogues.state;
    if (pendingCatalogues.revision == _accountCatalogueRevision) {
      _accountCatalogueRefreshPending = false;
    }
    _scheduleDeferredThreadEventDrain();
    return next;
  }

  late MobileCodexComposerDraftStore _draftStore;
  Map<String, String> get _pendingSubmissionIds =>
      _draftStore.submissionIdsFor(hostId, tabId, _threadId);
  bool _steering = false;

  Future<bool> send(
    String text, {
    List<Map<String, Object?>> attachments = const <Map<String, Object?>>[],
    List<Map<String, Object?>> catalogSelections =
        const <Map<String, Object?>>[],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty && catalogSelections.isEmpty) {
      return false;
    }
    final message = <String, Object?>{
      'id': _newClientMessageId(),
      'text': trimmed,
      'attachments': attachments,
      'catalogSelections': mobileCodexTrimCatalogSelections(
        text,
        catalogSelections,
      ),
    };
    final current = state.value ?? const MobileCodexState();
    if (state.isLoading || state.hasError || current.historyOutdated) {
      return false;
    }
    if (!current.supportsSharedQueue &&
        (current.busy || current.queuePaused || _sessionTransitionInProgress)) {
      state = AsyncData(
        current.copyWith(
          queuedMessages: <Map<String, Object?>>[
            ...current.queuedMessages,
            message,
          ],
        ),
      );
      return true;
    }
    final attempts = _draftStore.messageAttemptsFor(hostId, tabId, _threadId);
    final signature = jsonEncode({...message}..remove('id'));
    final id = attempts.claim(signature, message['id']! as String);
    message['id'] = id;
    var accepted = false;
    try {
      accepted = await _sendNow(message);
      return accepted;
    } finally {
      if (!accepted) attempts.retainForRetry(signature, id);
    }
  }

  @override
  Future<bool> _sendNow(Map<String, Object?> message) =>
      _deliverMessage(message);

  Future<void> stop() => _stopCapturedTurn();

  Future<bool> steer(
    String text, {
    List<Map<String, Object?>> attachments = const <Map<String, Object?>>[],
    List<Map<String, Object?>> catalogSelections =
        const <Map<String, Object?>>[],
  }) async {
    final client = _client;
    final current = state.value;
    if (_steering ||
        state.isLoading ||
        state.hasError ||
        client == null ||
        current?.activeTurnId == null ||
        current?.interrupting == true ||
        current?.historyLocked == true ||
        (text.trim().isEmpty &&
            attachments.isEmpty &&
            catalogSelections.isEmpty)) {
      return false;
    }
    final message = <String, Object?>{
      'text': text.trim(),
      'attachments': attachments,
      'catalogSelections': mobileCodexTrimCatalogSelections(
        text,
        catalogSelections,
      ),
    };
    final generation = _threadGeneration;
    final submissionIds = _pendingSubmissionIds;
    final signature = jsonEncode([
      'steer',
      _threadId,
      current!.activeTurnId,
      message,
    ]);
    final id = submissionIds.putIfAbsent(signature, _newClientMessageId);
    _steering = true;
    try {
      final response = await client.codexRequest(
        current.supportsSharedQueue ? 'codex.queue.add' : 'codex.turn.steer',
        <String, Object?>{
          'expectedThreadId': _threadId,
          'expectedHistoryRevision': current.historyRevision,
          'draft': message,
          'tabId': tabId,
          'turnId': current.activeTurnId,
          'clientUserMessageId': id,
          'input': _input(message, current),
          'userMessage': _userMessagePresentation(
            message,
            cwd: current.activeCwd,
          ),
        },
      );
      submissionIds.remove(signature);
      if (ref.mounted &&
          generation == _threadGeneration &&
          current.supportsSharedQueue) {
        _update((value) => _withSharedQueue(value, response));
      }
      return true;
    } catch (error, stackTrace) {
      if (ref.mounted && generation == _threadGeneration) {
        _setError(error, stackTrace);
      }
      return false;
    } finally {
      _steering = false;
    }
  }

  Future<void> respondApproval(
    MobileCodexPendingRequest request, {
    required Object decision,
  }) async {
    final decisionName = request.approvalDecisionName(decision);
    final accepted =
        decisionName == 'accept' || decisionName == 'acceptForSession';
    if (request.isPermissionsRequest) {
      await _respond(request, <String, Object?>{
        'permissions': accepted
            ? _permissionSubset(request.params['permissions'])
            : const <String, Object?>{},
        'scope': decisionName == 'acceptForSession' ? 'session' : 'turn',
      });
      return;
    }
    await _respond(request, <String, Object?>{
      'decision': request.approvalWireDecision(decision),
    });
  }

  Future<void> respondQuestion(
    MobileCodexPendingRequest request,
    Map<String, List<String>> answers,
  ) async {
    await _respond(request, <String, Object?>{
      'answers': <String, Object?>{
        for (final entry in answers.entries)
          entry.key: <String, Object?>{'answers': entry.value},
      },
    });
  }

  Future<void> snoozeQuestionAutoResolution(
    MobileCodexPendingRequest request,
  ) async {
    if (request.isBlocking) return;
    final client = _client;
    if (client == null) return;
    try {
      await client.codexRequest('codex.request.snooze', <String, Object?>{
        'requestId': request.id,
      });
    } catch (error, stackTrace) {
      _logger.fine(
        'The runtime host does not support snoozing Codex questions.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> respondElicitation(
    MobileCodexPendingRequest request, {
    required String action,
    Map<String, Object?> content = const <String, Object?>{},
  }) async {
    await _respond(request, <String, Object?>{
      'action': action,
      if (action == 'accept') 'content': content,
    });
  }

  Future<void> rejectRequest(MobileCodexPendingRequest request) async {
    await _respondError(request, <String, Object?>{
      'code': -32601,
      'message': 'Alera does not support this Codex request.',
    });
  }

  Future<void> _respond(
    MobileCodexPendingRequest request,
    Map<String, Object?> result,
  ) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.codexRequest('codex.response', <String, Object?>{
        'requestId': request.id,
        'result': result,
      });
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
    }
  }

  Future<void> _respondError(
    MobileCodexPendingRequest request,
    Map<String, Object?> error,
  ) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.codexRequest('codex.response', <String, Object?>{
        'requestId': request.id,
        'error': error,
      });
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
    }
  }

  void _persistCurrentConfiguration() {
    final current = state.value;
    if (current == null) return;
    final client = _client;
    if (client != null) {
      unawaited(
        client
            .codexRequest('codex.tab.configure', <String, Object?>{
              'tabId': tabId,
              'configuration': _mobileConfigurationPayload(current),
            })
            .catchError((Object error, StackTrace stackTrace) {
              _logger.warning(
                'Codex tab configuration could not be saved.',
                error,
                stackTrace,
              );
              return <String, Object?>{};
            }),
      );
    }
    MobileCodexPreferencesRepository repository;
    try {
      repository = ref.read(mobileCodexPreferencesRepositoryProvider);
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'Codex preferences repository was unavailable.',
        error,
        stackTrace,
      );
      return;
    }
    unawaited(
      repository
          .save(
            hostId,
            MobileCodexPreferences(
              model: current.selectedModel,
              reasoningEffort: current.reasoningEffort,
              speedMode: current.speedMode,
              permissionMode: current.permissionMode,
              planMode: current.planMode,
            ),
          )
          .catchError((Object error, StackTrace stackTrace) {
            _logger.warning(
              'Codex preferences could not be saved.',
              error,
              stackTrace,
            );
          }),
    );
  }

  Future<void> compact() => _simpleRequest('codex.thread.compact');

  Future<void> rename(String title) => _simpleRequest(
    'codex.thread.rename',
    <String, Object?>{'tabId': tabId, 'name': title.trim()},
  );
}
