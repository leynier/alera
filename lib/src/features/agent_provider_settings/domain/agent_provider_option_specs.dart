/// How Settings edits one provider-specific launch option.
enum AgentProviderOptionKind { text, toggle, secret }

/// A provider option the runtime's launch builder accepts. The keys mirror the
/// allow-list in `production_launch_config.rs`; an option the host stores
/// that is not listed here is kept untouched on save.
class const AgentProviderOptionSpec({
  required final String key,
  required final String label,
  required final String description,
  final AgentProviderOptionKind kind = AgentProviderOptionKind.text,
}) {
  /// The write-only secret target name for this option.
  String get secretName => agentProviderOptionSecretName(key);
}

String agentProviderOptionSecretName(String key) => 'option:$key';

List<AgentProviderOptionSpec> agentProviderOptionSpecs(String provider) =>
    switch (provider) {
      'grok' => const <AgentProviderOptionSpec>[
        AgentProviderOptionSpec(
          key: 'authMethod',
          label: 'Sign-In Method',
          description: 'The ACP authentication method Grok should use.',
        ),
      ],
      'antigravity' => const <AgentProviderOptionSpec>[
        AgentProviderOptionSpec(
          key: 'profileDir',
          label: 'Profile Directory',
          description: 'Directory Antigravity keeps its profile in.',
        ),
        AgentProviderOptionSpec(
          key: 'authMethodId',
          label: 'Sign-In Method',
          description: 'The ACP authentication method id.',
        ),
      ],
      'acpRegistry' => const <AgentProviderOptionSpec>[
        AgentProviderOptionSpec(
          key: 'agentId',
          label: 'Agent Id',
          description: 'The ACP registry agent this instance launches.',
        ),
        AgentProviderOptionSpec(
          key: 'authMethodId',
          label: 'Sign-In Method',
          description: 'The ACP authentication method id.',
        ),
      ],
      'cursor' => const <AgentProviderOptionSpec>[
        AgentProviderOptionSpec(
          key: 'bridgeUrl',
          label: 'Bridge URL',
          description: 'Endpoint of the Cursor SDK bridge.',
        ),
        AgentProviderOptionSpec(
          key: 'allowRemoteBridge',
          label: 'Allow Remote Bridge',
          description: 'Accept a bridge URL that is not on this host.',
          kind: AgentProviderOptionKind.toggle,
        ),
        AgentProviderOptionSpec(
          key: 'bridgeBearerToken',
          label: 'Bridge Token',
          description: 'Bearer token the bridge expects.',
          kind: AgentProviderOptionKind.secret,
        ),
        AgentProviderOptionSpec(
          key: 'bearerToken',
          label: 'Bearer Token',
          description: 'Bearer token for the Cursor API.',
          kind: AgentProviderOptionKind.secret,
        ),
        AgentProviderOptionSpec(
          key: 'apiKey',
          label: 'API Key',
          description: 'Cursor API key.',
          kind: AgentProviderOptionKind.secret,
        ),
      ],
      'opencode' => const <AgentProviderOptionSpec>[
        AgentProviderOptionSpec(
          key: 'serverUrl',
          label: 'Server URL',
          description:
              'Connect to a running OpenCode server instead of '
              'starting one.',
        ),
        AgentProviderOptionSpec(
          key: 'serverPassword',
          label: 'Server Password',
          description: 'Password of that OpenCode server.',
          kind: AgentProviderOptionKind.secret,
        ),
        AgentProviderOptionSpec(
          key: 'generation',
          label: 'Generation',
          description: 'OpenCode release line to talk to, such as v1 or v2.',
        ),
      ],
      _ => const <AgentProviderOptionSpec>[],
    };

/// Providers a person can add another instance of, in the order the Add
/// Provider form lists them.
const List<String> agentProviderKinds = <String>[
  'codex',
  'claudeAgent',
  'cursor',
  'opencode',
  'grok',
  'antigravity',
  'pi',
  'muse',
  'acpRegistry',
];
