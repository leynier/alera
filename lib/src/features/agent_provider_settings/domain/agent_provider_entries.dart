import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_instance_draft.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';

/// One row of the Providers list: what the host's catalog reports about the
/// instance, what it stores for it, or an instance Add Provider created that
/// is not saved yet.
class const AgentProviderEntry({
  required final String id,
  required final String provider,
  required final String label,
  required final bool enabled,
  final AgentChatProviderInstance? catalog,
  final AgentChatProviderInstanceEnvelope? envelope,
  final AgentProviderInstanceDraft? unsavedDraft,
}) {
  bool get unsaved => unsavedDraft != null;

  /// The draft this row starts editing from: the stored envelope, the
  /// unsaved draft, or the defaults of a catalog-only instance.
  AgentProviderInstanceDraft seed() {
    if (unsavedDraft case final draft?) {
      return draft;
    }
    if (envelope case final stored?) {
      return AgentProviderInstanceDraft.fromEnvelope(stored);
    }
    return AgentProviderInstanceDraft(
      providerInstanceId: id,
      provider: provider,
      enabled: enabled,
    );
  }
}

/// What an instance is called when its own label is empty, matching the
/// host's built-in provider labels. The catalog row's label cannot serve:
/// it already carries the instance's customized label.
String agentProviderDefaultLabel(String provider) => switch (provider) {
  'claudeAgent' => 'Claude Code',
  _ => agentChatProviderFallbackLabel(provider),
};

/// The catalog's rows in catalog order, then stored instances the catalog
/// did not report (for example one the host could not resolve), then the
/// unsaved instance. Labels prefer the stored label, then the catalog's.
List<AgentProviderEntry> agentProviderEntries({
  required List<AgentChatProviderInstance> catalog,
  required AgentChatProviderSettingsSnapshot? snapshot,
  AgentProviderInstanceDraft? unsavedNew,
}) {
  final stored = <String, AgentChatProviderInstanceEnvelope>{
    for (final envelope
        in snapshot?.instances ?? const <AgentChatProviderInstanceEnvelope>[])
      envelope.providerInstanceId: envelope,
  };
  String labelOf(String provider, String? storedLabel, String? catalogLabel) {
    final trimmed = storedLabel?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return catalogLabel ?? agentProviderDefaultLabel(provider);
  }

  final entries = <AgentProviderEntry>[];
  final seen = <String>{};
  for (final row in catalog) {
    if (!seen.add(row.id)) {
      continue;
    }
    final envelope = stored[row.id];
    entries.add(
      AgentProviderEntry(
        id: row.id,
        provider: row.provider,
        label: labelOf(row.provider, envelope?.label, row.label),
        enabled: envelope?.enabled ?? row.enabled,
        catalog: row,
        envelope: envelope,
      ),
    );
  }
  for (final envelope in stored.values) {
    if (!seen.add(envelope.providerInstanceId)) {
      continue;
    }
    entries.add(
      AgentProviderEntry(
        id: envelope.providerInstanceId,
        provider: envelope.provider,
        label: labelOf(envelope.provider, envelope.label, null),
        enabled: envelope.enabled,
        envelope: envelope,
      ),
    );
  }
  if (unsavedNew != null && seen.add(unsavedNew.providerInstanceId)) {
    entries.add(
      AgentProviderEntry(
        id: unsavedNew.providerInstanceId,
        provider: unsavedNew.provider,
        label: labelOf(unsavedNew.provider, unsavedNew.label, null),
        enabled: unsavedNew.enabled,
        unsavedDraft: unsavedNew,
      ),
    );
  }
  return List.unmodifiableOf(entries);
}
