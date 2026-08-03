import 'dart:async';

import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_codex_controller.g.dart';
part 'mobile_codex_controller_helpers.dart';

@riverpod
Future<MobileCodexClient> mobileCodexClient(Ref ref, String hostId) =>
    ref.watch(hostConnectionControllerProvider(hostId).future);

@riverpod
class MobileCodexController extends _$MobileCodexController {
  final Logger _logger = Logger('MobileCodexController');
  MobileCodexClient? _client;
  StreamSubscription<MobileRuntimeEvent>? _events;
  Timer? _interruptSafetyTimer;

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
      _events?.cancel();
    });
    final response = await client.codexRequest(
      'codex.thread.open',
      <String, Object?>{'tabId': tabId},
    );
    var next = MobileCodexState.fromSnapshot(response['snapshot']);
    next = next.copyWith(selectedModel: _string(response['model']));
    next = await _loadCatalogues(client, next);
    return next;
  }

  Future<MobileCodexState> _loadCatalogues(
    MobileCodexClient client,
    MobileCodexState current,
  ) async {
    var next = current;
    try {
      final payload = await client.codexRequest('codex.model.list');
      final discovered = _modelItems(payload);
      final models = discovered.isEmpty
          ? const <MobileCodexModelOption>[
              MobileCodexModelOption(id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol'),
            ]
          : discovered;
      final selected = models.any((model) => model.id == next.selectedModel)
          ? next.selectedModel
          : null;
      next = next.copyWith(
        models: models,
        selectedModel:
            selected ??
            models.where((model) => model.isDefault).firstOrNull?.id ??
            models.first.id,
      );
    } catch (error, stackTrace) {
      _logger.warning(
        'Codex model discovery was unavailable.',
        error,
        stackTrace,
      );
      next = next.copyWith(
        models: const <MobileCodexModelOption>[
          MobileCodexModelOption(id: 'gpt-5.6-sol', label: 'GPT-5.6 Sol'),
        ],
        selectedModel: next.selectedModel ?? 'gpt-5.6-sol',
      );
    }
    final selectedOption = next.models
        .where((model) => model.id == next.selectedModel)
        .firstOrNull;
    next = next.copyWith(
      reasoningEffort: _supportedEffort(selectedOption, next.reasoningEffort),
      speedMode: selectedOption?.supportsFastMode == false
          ? 'normal'
          : next.speedMode,
    );
    next = next.copyWith(
      collaborationModes: await _optionalItems(
        client,
        'codex.collaborationModes.list',
      ),
      skills: await _optionalItems(
        client,
        'codex.skills.list',
        includeTabId: true,
      ),
      apps: await _optionalItems(client, 'codex.apps.list', includeTabId: true),
    );
    return next;
  }

  Future<List<Map<String, Object?>>> _optionalItems(
    MobileCodexClient client,
    String request, {
    bool includeTabId = false,
  }) async {
    try {
      final payload = await client.codexRequest(
        request,
        includeTabId
            ? <String, Object?>{'tabId': tabId}
            : const <String, Object?>{},
      );
      final value =
          payload['data'] ??
          payload['items'] ??
          payload['apps'] ??
          payload['skills'] ??
          payload['collaborationModes'] ??
          payload['modes'];
      return value is List
          ? <Map<String, Object?>>[
              for (final item in value)
                if (item is Map) Map<String, Object?>.from(item),
            ]
          : const <Map<String, Object?>>[];
    } catch (error, stackTrace) {
      _logger.warning(
        'Optional Codex catalogue was unavailable.',
        error,
        stackTrace,
      );
      return const <Map<String, Object?>>[];
    }
  }

  Future<void> send(
    String text, {
    List<Map<String, Object?>> attachments = const <Map<String, Object?>>[],
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    final message = <String, Object?>{
      'text': trimmed,
      'attachments': attachments,
    };
    final current = state.value ?? const MobileCodexState();
    if (current.busy) {
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

  Future<void> _sendNow(Map<String, Object?> message) async {
    final client = _client;
    if (client == null) return;
    final current = state.value ?? const MobileCodexState();
    state = AsyncData(current.copyWith(sending: true, error: null));
    try {
      await client.codexRequest('codex.turn.start', <String, Object?>{
        'tabId': tabId,
        'input': _input(message, current),
        'model': current.selectedModel,
        'reasoning': <String, Object?>{'effort': current.reasoningEffort},
        'effort': current.reasoningEffort,
        'serviceTier': current.speedMode == 'fast' ? 'fast' : null,
        'approvalPolicy': current.permissionMode,
        if (current.planMode || current.collaborationMode != null)
          'collaborationMode': <String, Object?>{
            'mode': current.collaborationMode ?? 'plan',
            'settings': <String, Object?>{
              'model': current.selectedModel,
              'reasoning_effort': current.reasoningEffort,
            },
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

  Future<void> steer(String text) async {
    final client = _client;
    final current = state.value;
    if (client == null ||
        current?.activeTurnId == null ||
        text.trim().isEmpty) {
      return;
    }
    try {
      await client.codexRequest('codex.turn.steer', <String, Object?>{
        'tabId': tabId,
        'turnId': current!.activeTurnId,
        'input': <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': text.trim()},
        ],
      });
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
    }
  }

  Future<void> respondApproval(
    MobileCodexPendingRequest request, {
    required bool accepted,
    bool forSession = false,
  }) async {
    await _respond(request, <String, Object?>{
      'decision': accepted ? 'accept' : 'decline',
      if (accepted && forSession)
        'acceptSettings': <String, Object?>{'forSession': true},
    });
  }

  Future<void> respondQuestion(
    MobileCodexPendingRequest request,
    Map<String, List<String>> answers,
  ) async {
    await _respond(request, <String, Object?>{'answers': answers});
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

  Future<void> implementPlan() => send('Implement the plan.');

  void setModel(String? model) {
    if (model == null || model.isEmpty) return;
    _update(
      (current) => current.copyWith(
        selectedModel: model,
        speedMode:
            current.models
                    .where((item) => item.id == model)
                    .firstOrNull
                    ?.supportsFastMode ==
                false
            ? 'normal'
            : current.speedMode,
        reasoningEffort: _supportedEffort(
          current.models.where((item) => item.id == model).firstOrNull,
          current.reasoningEffort,
        ),
      ),
    );
  }

  void setReasoning(String effort) => _update(
    (current) => current.copyWith(
      reasoningEffort: _supportedEffort(
        current.models
            .where((item) => item.id == current.selectedModel)
            .firstOrNull,
        effort,
      ),
    ),
  );
  void setSpeed(String speed) => _update((current) {
    final model = current.models
        .where((item) => item.id == current.selectedModel)
        .firstOrNull;
    return current.copyWith(
      speedMode: speed == 'fast' && model?.supportsFastMode == false
          ? 'normal'
          : speed,
    );
  });
  void setPermissionMode(String mode) =>
      _update((current) => current.copyWith(permissionMode: mode));
  void setPlanMode(bool enabled) => _update(
    (current) => current.copyWith(
      planMode: enabled,
      collaborationMode: enabled
          ? 'plan'
          : current.collaborationMode == 'plan'
          ? null
          : current.collaborationMode,
    ),
  );
  void setCollaborationMode(String? mode) {
    if (mode == null || mode.isEmpty) return;
    _update(
      (current) =>
          current.copyWith(collaborationMode: mode, planMode: mode == 'plan'),
    );
  }

  void clearError() => _update((current) => current.copyWith(error: null));

  void removeQueuedMessage(int index) => _update((current) {
    if (index < 0 || index >= current.queuedMessages.length) return current;
    final next = <Map<String, Object?>>[...current.queuedMessages]
      ..removeAt(index);
    return current.copyWith(queuedMessages: next);
  });

  void editQueuedMessage(int index, String text) => _update((current) {
    if (index < 0 || index >= current.queuedMessages.length) return current;
    final next = <Map<String, Object?>>[...current.queuedMessages];
    next[index] = <String, Object?>{...next[index], 'text': text.trim()};
    return current.copyWith(queuedMessages: next);
  });

  void _onEvent(MobileRuntimeEvent event) {
    if (event.name == 'codexServerChanged') {
      final current = state.value;
      if (current == null) return;
      final status = event.payload['status']?.toString();
      if (status == 'error') {
        _logger.warning(
          'Codex app-server reported an error.',
          event.payload['error'],
        );
        state = AsyncData(
          current.copyWith(
            error: _safeError(event.payload['error'] ?? 'Codex server failed.'),
          ),
        );
      }
      return;
    }
    if (event.name != 'codexThreadChanged' || event.payload['tabId'] != tabId) {
      return;
    }
    final next = MobileCodexState.fromSnapshot(event.payload['snapshot']);
    final current = state.value;
    if (current == null) return;
    if (!next.busy) _interruptSafetyTimer?.cancel();
    state = AsyncData(
      next.copyWith(
        models: current.models,
        collaborationModes: current.collaborationModes,
        skills: current.skills,
        apps: current.apps,
        selectedModel: current.selectedModel,
        reasoningEffort: current.reasoningEffort,
        speedMode: current.speedMode,
        permissionMode: current.permissionMode,
        planMode: current.planMode,
        collaborationMode: current.collaborationMode,
        queuedMessages: current.queuedMessages,
        sending: next.busy ? current.sending : false,
        interrupting: next.busy ? current.interrupting : false,
        error: null,
      ),
    );
    if (!next.busy && current.queuedMessages.isNotEmpty) {
      final message = current.queuedMessages.first;
      _update(
        (value) => value.copyWith(
          queuedMessages: value.queuedMessages.skip(1).toList(growable: false),
        ),
      );
      unawaited(_sendNow(message));
    }
  }

  Future<void> _simpleRequest(
    String request, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    final client = _client;
    if (client == null) return;
    try {
      await client.codexRequest(request, <String, Object?>{
        'tabId': tabId,
        ...payload,
      });
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
    }
  }

  void _update(MobileCodexState Function(MobileCodexState) update) {
    final current = state.value;
    if (current != null) state = AsyncData(update(current));
  }

  void _setError(Object error, StackTrace stackTrace) {
    _logger.warning('Codex request failed.', error, stackTrace);
    if (!ref.mounted) {
      Error.throwWithStackTrace(error, stackTrace);
    }
    _update(
      (current) => current.copyWith(
        sending: false,
        interrupting: false,
        error: _safeError(error),
      ),
    );
  }
}
