import 'dart:async';
import 'dart:convert';

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
part 'mobile_codex_controller_lifecycle.dart';
part 'mobile_codex_controller_workspace.dart';
part 'mobile_codex_controller_options.dart';
part 'mobile_codex_controller_sessions.dart';
part 'mobile_codex_controller_catalogues.dart';

@riverpod
Future<MobileCodexClient> mobileCodexClient(Ref ref, String hostId) =>
    ref.watch(hostConnectionControllerProvider(hostId).future);

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

  @override
  bool get _sessionTransitionInProgress => _sessionTransitionCount > 0;

  bool get supportsSessions => _client?.supportsCodexSessions == true;

  bool get supportsTurnPolicy => _client?.supportsCodexTurnPolicy == true;

  int get threadGeneration => _threadGeneration;

  @override
  Timer? get _interruptSafetyTimerValue => _interruptSafetyTimer;

  @override
  Future<void> _reloadCatalogue(String catalog) =>
      _reloadMobileCodexCatalogue(catalog);

  @override
  Future<MobileCodexState> build(String hostId, String tabId) async {
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
      activeCwd: _string(response['cwd']),
      historyNextCursor: _string(response['historyNextCursor']),
      recovery: response['recovery'] == null
          ? null
          : MobileCodexThreadRecovery.fromJson(response['recovery']),
    );
    next = _applyMobileConfiguration(next, storedConfiguration);
    next = await _loadCatalogues(client, next);
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
    _scheduleDeferredThreadEventDrain();
    return next;
  }

  Future<void> send(
    String text, {
    List<Map<String, Object?>> attachments = const <Map<String, Object?>>[],
    List<Map<String, Object?>> catalogSelections =
        const <Map<String, Object?>>[],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty && catalogSelections.isEmpty) {
      return;
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
    if (current.busy || _sessionTransitionInProgress) {
      state = AsyncData(
        current.copyWith(
          queuedMessages: <Map<String, Object?>>[
            ...current.queuedMessages,
            message,
          ],
        ),
      );
      return;
    }
    await _sendNow(message);
  }

  @override
  Future<void> _sendNow(Map<String, Object?> message) async {
    final client = _client;
    if (client == null) return;
    final current = state.value ?? const MobileCodexState();
    final supportsTurnPolicy = client.supportsCodexTurnPolicy;
    final wirePermissionMode =
        !supportsTurnPolicy && current.permissionMode == 'auto-review'
        ? 'on-request'
        : current.permissionMode;
    state = AsyncData(current.copyWith(sending: true, error: null));
    try {
      await client.codexRequest('codex.turn.start', <String, Object?>{
        'tabId': tabId,
        'expectedThreadId': _threadId,
        'clientUserMessageId':
            message['id']?.toString() ?? _newClientMessageId(),
        'input': _input(message, current),
        'userMessage': _userMessagePresentation(
          message,
          cwd: current.activeCwd,
        ),
        'model': current.selectedModel,
        'reasoning': <String, Object?>{'effort': current.reasoningEffort},
        'effort': current.reasoningEffort,
        'serviceTier': current.speedMode == 'fast' ? 'fast' : null,
        'approvalPolicy': supportsTurnPolicy
            ? switch (current.permissionMode) {
                'never' => 'never',
                'untrusted' => 'untrusted',
                _ => 'on-request',
              }
            : wirePermissionMode,
        if (supportsTurnPolicy)
          'approvalsReviewer': current.permissionMode == 'auto-review'
              ? 'auto_review'
              : 'user',
        if (supportsTurnPolicy)
          'sandboxPolicy': current.permissionMode == 'never'
              ? <String, Object?>{'type': 'dangerFullAccess'}
              : <String, Object?>{
                  'type': 'workspaceWrite',
                  'writableRoots': const <String>[],
                  'networkAccess': false,
                },
        'collaborationMode': <String, Object?>{
          'mode':
              current.collaborationMode ??
              (current.planMode ? 'plan' : 'default'),
          'settings': <String, Object?>{
            'model': current.selectedModel,
            'reasoning_effort': current.reasoningEffort,
          },
        },
        'configuration': <String, Object?>{
          ..._mobileConfigurationPayload(current),
          'permissionMode': wirePermissionMode,
        },
      });
      if (ref.mounted) {
        state = AsyncData((state.value ?? current).copyWith(sending: false));
      }
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
    }
  }

  Future<void> stop() async {
    final client = _client;
    final current = state.value;
    if (client == null ||
        current == null ||
        current.activeTurnId == null ||
        current.interrupting) {
      return;
    }
    _update((value) => value.copyWith(interrupting: true, error: null));
    _interruptSafetyTimer?.cancel();
    _interruptSafetyTimer = Timer(const Duration(seconds: 2), () {
      if (ref.mounted) {
        _update((value) => value.copyWith(interrupting: false, sending: false));
      }
    });
    try {
      await client.codexRequest('codex.turn.interrupt', <String, Object?>{
        'tabId': tabId,
        'turnId': current.activeTurnId,
      });
    } catch (error, stackTrace) {
      _interruptSafetyTimer?.cancel();
      _setError(error, stackTrace);
    }
  }

  Future<void> steer(
    String text, {
    List<Map<String, Object?>> attachments = const <Map<String, Object?>>[],
    List<Map<String, Object?>> catalogSelections =
        const <Map<String, Object?>>[],
  }) async {
    final client = _client;
    final current = state.value;
    if (client == null ||
        current?.activeTurnId == null ||
        (text.trim().isEmpty &&
            attachments.isEmpty &&
            catalogSelections.isEmpty)) {
      return;
    }
    final message = <String, Object?>{
      'text': text.trim(),
      'attachments': attachments,
      'catalogSelections': mobileCodexTrimCatalogSelections(
        text,
        catalogSelections,
      ),
    };
    try {
      await client.codexRequest('codex.turn.steer', <String, Object?>{
        'tabId': tabId,
        'turnId': current!.activeTurnId,
        'clientUserMessageId': _newClientMessageId(),
        'input': _input(message, current),
        'userMessage': _userMessagePresentation(
          message,
          cwd: current.activeCwd,
        ),
      });
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
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

  Future<void> review({
    String target = 'uncommittedChanges',
    String? argument,
    String? delivery,
  }) {
    final targetPayload = <String, Object?>{'type': target};
    if (argument != null && argument.trim().isNotEmpty) {
      switch (target) {
        case 'baseBranch':
          targetPayload['branch'] = argument.trim();
        case 'commit':
          targetPayload['sha'] = argument.trim();
        case 'custom':
          targetPayload['instructions'] = argument.trim();
      }
    }
    return _simpleRequest('codex.review.start', <String, Object?>{
      'tabId': tabId,
      'target': targetPayload,
      if (delivery != null && delivery.isNotEmpty) 'delivery': delivery,
    });
  }

  Future<void> rename(String title) => _simpleRequest(
    'codex.thread.rename',
    <String, Object?>{'tabId': tabId, 'name': title.trim()},
  );
}
