import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_option_specs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('provider options match their launch fields and secret targets', () {
    final expected = <String, Map<String, AgentProviderOptionKind>>{
      'grok': <String, AgentProviderOptionKind>{
        'authMethod': AgentProviderOptionKind.text,
      },
      'antigravity': <String, AgentProviderOptionKind>{
        'profileDir': AgentProviderOptionKind.text,
        'authMethodId': AgentProviderOptionKind.text,
      },
      'acpRegistry': <String, AgentProviderOptionKind>{
        'agentId': AgentProviderOptionKind.text,
        'authMethodId': AgentProviderOptionKind.text,
      },
      'cursor': <String, AgentProviderOptionKind>{
        'bridgeUrl': AgentProviderOptionKind.text,
        'allowRemoteBridge': AgentProviderOptionKind.toggle,
        'bridgeBearerToken': AgentProviderOptionKind.secret,
        'bearerToken': AgentProviderOptionKind.secret,
        'apiKey': AgentProviderOptionKind.secret,
      },
      'opencode': <String, AgentProviderOptionKind>{
        'serverUrl': AgentProviderOptionKind.text,
        'serverPassword': AgentProviderOptionKind.secret,
        'generation': AgentProviderOptionKind.text,
      },
    };
    for (final MapEntry(:key, :value) in expected.entries) {
      final specs = agentProviderOptionSpecs(key);
      expect(<String, AgentProviderOptionKind>{
        for (final spec in specs) spec.key: spec.kind,
      }, value);
      for (final spec in specs) {
        expect(spec.label, isNotEmpty);
        expect(spec.description, isNotEmpty);
        if (spec.kind == AgentProviderOptionKind.secret) {
          expect(spec.secretName, 'option:${spec.key}');
        }
      }
    }
    expect(agentProviderOptionSpecs('codex'), isEmpty);
    expect(agentProviderOptionSpecs('unknown'), isEmpty);
  });

  test('an option defaults to text and derives its write-only target name', () {
    final spec = AgentProviderOptionSpec(
      key: 'apiKey',
      label: 'API Key',
      description: 'An API key.',
    );
    expect(spec.kind, AgentProviderOptionKind.text);
    expect(spec.secretName, 'option:apiKey');
  });
}
