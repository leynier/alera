part of 'mobile_codex_controller.dart';

// ignore_for_file: invalid_use_of_protected_member

extension MobileCodexControllerOptions on MobileCodexController {
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
    _persistCurrentConfiguration();
  }

  void setReasoning(String effort) {
    _update(
      (current) => current.copyWith(
        reasoningEffort: _supportedEffort(
          current.models
              .where((item) => item.id == current.selectedModel)
              .firstOrNull,
          effort,
        ),
      ),
    );
    _persistCurrentConfiguration();
  }

  void setSpeed(String speed) {
    _update((current) {
      final model = current.models
          .where((item) => item.id == current.selectedModel)
          .firstOrNull;
      return current.copyWith(
        speedMode: speed == 'fast' && model?.supportsFastMode == false
            ? 'normal'
            : speed,
      );
    });
    _persistCurrentConfiguration();
  }

  void setPermissionMode(String mode) {
    _update((current) => current.copyWith(permissionMode: mode));
    _persistCurrentConfiguration();
  }

  void setPlanMode(bool enabled) {
    _update(
      (current) => current.copyWith(
        planMode: enabled,
        collaborationMode: enabled
            ? 'plan'
            : current.collaborationMode == 'plan'
            ? null
            : current.collaborationMode,
      ),
    );
    _persistCurrentConfiguration();
  }

  void setCollaborationMode(String? mode) {
    if (mode?.isEmpty == true) return;
    _update(
      (current) =>
          current.copyWith(collaborationMode: mode, planMode: mode == 'plan'),
    );
    _persistCurrentConfiguration();
  }

  Future<void> implementPlan() async {
    setPlanMode(false);
    await send('Implement plan');
  }

  Future<void> declinePlan() async {
    setPlanMode(true);
    await send('Do not implement the plan.');
  }

  Future<void> refinePlan(String refinement) async {
    final text = refinement.trim();
    if (text.isEmpty) return;
    setPlanMode(true);
    await send(text);
  }

  void clearError() => _update((current) => current.copyWith(error: null));

  Future<void> recoverThread() async {
    final client = _client;
    if (client == null) return;
    final expectedThreadId = _threadId;
    if (expectedThreadId == null) {
      _update(
        (current) => current.copyWith(
          error:
              'The Codex conversation changed before recovery. Review the current conversation and try again.',
        ),
      );
      return;
    }
    _beginMobileSessionTransition();
    try {
      final response = await client.codexRequest(
        'codex.thread.recover',
        <String, Object?>{'tabId': tabId, 'expectedThreadId': expectedThreadId},
      );
      if (!ref.mounted) return;
      _sessionTransitionSucceeded = true;
      _threadId = _string(response['threadId']);
      _threadGeneration += 1;
      final recovered = MobileCodexState.fromSnapshot(response['snapshot']);
      _update(
        (current) => _applyMobileConfiguration(
          recovered.copyWith(
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
            activeCwd: _string(response['cwd']) ?? current.activeCwd,
            historyNextCursor: null,
            recovery: null,
            error: null,
          ),
          response['configuration'],
        ),
      );
    } catch (error, stackTrace) {
      _setError(error, stackTrace);
    } finally {
      _finishMobileSessionTransition();
    }
  }

  void removeQueuedMessage(int index) => _update((current) {
    if (index < 0 || index >= current.queuedMessages.length) return current;
    final next = <Map<String, Object?>>[...current.queuedMessages]
      ..removeAt(index);
    return current.copyWith(queuedMessages: next);
  });

  void editQueuedMessage(
    int index,
    String text, {
    List<Map<String, Object?>>? catalogSelections,
  }) => _update((current) {
    if (index < 0 || index >= current.queuedMessages.length) return current;
    final next = <Map<String, Object?>>[...current.queuedMessages];
    final editedText = text.trim();
    final message = next[index];
    final selections =
        catalogSelections ??
        (message['catalogSelections'] is List
            ? <Map<String, Object?>>[
                for (final value in message['catalogSelections']! as List)
                  if (value is Map) Map<String, Object?>.from(value),
              ]
            : const <Map<String, Object?>>[]);
    next[index] = <String, Object?>{
      ...message,
      'text': editedText,
      'catalogSelections': mobileCodexTrimCatalogSelections(text, selections),
    };
    return current.copyWith(queuedMessages: next);
  });
}
