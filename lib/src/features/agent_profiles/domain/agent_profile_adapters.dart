import 'package:alera/src/features/agent_status/domain/agent_status.dart';

/// The agent adapters a profile may target.
///
/// The source of truth is `AGENT_ADAPTERS` in
/// `rust/alera-cli/src/terminal_host/orchestration/agent_registry.rs`: an
/// adapter defines how the host detects readiness, injects the dispatch
/// preamble, and forces submission, so a profile pointing anywhere else could
/// never be made ready. The host rejects an unknown adapter, so drift here
/// surfaces as a refused save rather than a broken worker.
///
/// `AgentType.grok` is deliberately absent: it is a supported agent-status hook
/// agent but has no spawn adapter.
const List<AgentType> spawnableAgentProfileAdapters = <AgentType>[
  AgentType.codex,
  AgentType.claude,
  AgentType.copilot,
  AgentType.cursor,
  AgentType.agy,
  AgentType.opencode,
  AgentType.opencode2,
  AgentType.pi,
  AgentType.amp,
];

/// The default launch command each adapter uses when a profile does not
/// override it. Mirrors `default_command` in the Rust registry.
const Map<AgentType, String> agentProfileDefaultCommands = <AgentType, String>{
  AgentType.codex: 'codex',
  AgentType.claude: 'claude',
  AgentType.copilot: 'copilot',
  AgentType.cursor: 'cursor-agent',
  AgentType.agy: 'agy',
  AgentType.opencode: 'opencode',
  AgentType.opencode2: 'opencode2',
  AgentType.pi: 'pi',
  AgentType.amp: 'amp',
};

AgentType? agentProfileAdapterFromKey(String key) {
  for (final adapter in spawnableAgentProfileAdapters) {
    if (adapter.key == key) {
      return adapter;
    }
  }
  return null;
}
