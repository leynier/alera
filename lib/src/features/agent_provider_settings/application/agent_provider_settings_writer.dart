import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_failure.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_instance_draft.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';

/// Applies provider settings changes on one host. Every mutation carries a
/// fresh request id and the revision it was based on; a dropped connection is
/// retried once with the same id, so the host replays its stored receipt
/// instead of applying the change twice.
final class AgentProviderSettingsWriter {
  AgentProviderSettingsWriter({
    required this._repository,
    required this._newRequestId,
    required this._hostId,
  });

  final AgentChatSettingsRepository _repository;
  final String Function() _newRequestId;
  final String? _hostId;

  /// Saves [draft] and then each pending secret, in that order, because a
  /// secret can only be written for a name the host already declares
  /// sensitive. [saved] is the draft as the host last stored it, or null for
  /// an instance with no override row yet. [onProgress] sees every snapshot
  /// the host returns, so a failure part way keeps the steps that applied.
  Future<AgentChatProviderSettingsSnapshot> save({
    required int revision,
    required AgentProviderInstanceDraft draft,
    required AgentProviderInstanceDraft? saved,
    List<AgentProviderPendingSecret> secrets =
        const <AgentProviderPendingSecret>[],
    void Function(AgentChatProviderSettingsSnapshot snapshot)? onProgress,
  }) async {
    final problems = draft.validate();
    if (problems.isNotEmpty) {
      throw AgentProviderSettingsFailure(
        kind: .rejected,
        message: problems.first,
      );
    }
    var current = revision;
    AgentChatProviderSettingsSnapshot? snapshot;
    final writable = agentProviderWritableSecrets(draft, secrets);
    final needsUpsert =
        draft.isNew ||
        saved == null ||
        draft.signature != saved.signature ||
        writable.any(
          (secret) => !secret.clears && !saved.acceptsSecret(secret.name),
        );
    if (needsUpsert) {
      final requestId = _newRequestId();
      final edit = draft.toEdit();
      final upserted = await _once<AgentChatProviderSettingsSnapshot>(
        () => _repository.upsertProviderInstance(
          requestId: requestId,
          expectedRevision: current,
          instance: edit,
          hostId: _hostId,
        ),
      );
      snapshot = upserted;
      current = upserted.revision;
      onProgress?.call(upserted);
    }
    for (final secret in writable) {
      final requestId = _newRequestId();
      final base = current;
      final value = secret.value;
      final AgentChatProviderSettingsSnapshot step;
      if (value == null) {
        if (!(saved?.acceptsSecret(secret.name) ?? false)) {
          continue;
        }
        step = await _once<AgentChatProviderSettingsSnapshot>(
          () => _repository.clearProviderSecret(
            requestId: requestId,
            expectedRevision: base,
            providerInstanceId: draft.providerInstanceId,
            name: secret.name,
            hostId: _hostId,
          ),
        );
      } else {
        step = await _once<AgentChatProviderSettingsSnapshot>(
          () => _repository.setProviderSecret(
            requestId: requestId,
            expectedRevision: base,
            providerInstanceId: draft.providerInstanceId,
            name: secret.name,
            value: value,
            hostId: _hostId,
          ),
        );
      }
      snapshot = step;
      current = step.revision;
      onProgress?.call(step);
    }
    return snapshot ?? AgentChatProviderSettingsSnapshot(revision: current);
  }

  /// Turns an instance on or off without touching its launch definition.
  Future<AgentChatProviderSettingsSnapshot> setEnabled({
    required int revision,
    required String providerInstanceId,
    required String provider,
    required bool enabled,
  }) {
    final requestId = _newRequestId();
    return _once(
      () => _repository.upsertProviderInstance(
        requestId: requestId,
        expectedRevision: revision,
        instance: AgentChatProviderInstanceEdit(
          providerInstanceId: providerInstanceId,
          provider: provider,
          enabled: enabled,
        ),
        hostId: _hostId,
      ),
    );
  }

  Future<AgentChatProviderRemovalImpact> removalImpact(
    String providerInstanceId,
  ) => _once(
    () => _repository.providerRemovalImpact(
      providerInstanceId: providerInstanceId,
      hostId: _hostId,
    ),
  );

  /// Removes an added instance, or a built-in instance's override row, which
  /// returns it to its defaults. Open chats are never closed or rewritten;
  /// [allowInUse] confirms the person saw them.
  Future<AgentChatProviderSettingsSnapshot> remove({
    required int revision,
    required String providerInstanceId,
    bool allowInUse = false,
  }) {
    final requestId = _newRequestId();
    return _once(
      () => _repository.removeProviderInstance(
        requestId: requestId,
        expectedRevision: revision,
        providerInstanceId: providerInstanceId,
        allowInUse: allowInUse,
        hostId: _hostId,
      ),
    );
  }

  Future<T> _once<T>(Future<T> Function() call) async {
    try {
      try {
        return await call();
      } on AgentChatConnectionException {
        return await call();
      }
    } on Object catch (error) {
      throw AgentProviderSettingsFailure.from(error);
    }
  }
}

/// The pending secrets that still belong to [draft]: a removed or renamed
/// environment variable takes its typed value with it rather than writing a
/// secret under a name nothing reads.
List<AgentProviderPendingSecret> agentProviderWritableSecrets(
  AgentProviderInstanceDraft draft,
  List<AgentProviderPendingSecret> secrets,
) {
  const prefix = 'option:';
  final options = draft.declaredSecretOptions;
  final environment = <String>{
    for (final entry in draft.environment)
      if (entry.sensitive) entry.name.trim(),
  };
  return <AgentProviderPendingSecret>[
    for (final secret in secrets)
      if (secret.name.startsWith(prefix)
          ? options.contains(secret.name.substring(prefix.length))
          : environment.contains(secret.name))
        secret,
  ];
}

/// Applies preference operations on one host. Operations are rebuilt from
/// the latest preferences after a revision conflict and sent once more, so a
/// concurrent edit on the phone is merged instead of overwritten.
final class AgentProviderPreferencesWriter {
  AgentProviderPreferencesWriter({
    required this._repository,
    required this._newRequestId,
    required this._hostId,
  });

  final AgentChatSettingsRepository _repository;
  final String Function() _newRequestId;
  final String? _hostId;

  Future<AgentChatPreferences> update(
    AgentChatPreferences current,
    List<AgentChatPreferenceOperation> Function(AgentChatPreferences latest)
    operations,
  ) async {
    try {
      return await _send(current, operations);
    } on AgentChatRequestException catch (error) {
      if (error.code != 'revisionConflict') {
        throw AgentProviderSettingsFailure.from(error);
      }
    } on Object catch (error) {
      throw AgentProviderSettingsFailure.from(error);
    }
    try {
      final latest = await _repository.preferences(hostId: _hostId);
      return await _send(latest, operations);
    } on Object catch (error) {
      throw AgentProviderSettingsFailure.from(error);
    }
  }

  Future<AgentChatPreferences> _send(
    AgentChatPreferences base,
    List<AgentChatPreferenceOperation> Function(AgentChatPreferences latest)
    operations,
  ) async {
    final input = AgentChatPreferencesUpdate(
      requestId: _newRequestId(),
      expectedRevision: base.revision,
      operations: operations(base),
    );
    try {
      return await _repository.updatePreferences(input, hostId: _hostId);
    } on AgentChatConnectionException {
      return _repository.updatePreferences(input, hostId: _hostId);
    }
  }
}
