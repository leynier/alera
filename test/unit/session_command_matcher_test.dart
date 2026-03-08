import 'package:alera/src/features/session/domain/commands/alera_command.dart';
import 'package:alera/src/features/session/domain/commands/command_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandRegistry.filter', () {
    const registry = CommandRegistry();

    test('prefers exact and prefix matches before fuzzy matches', () {
      final commands = <AleraCommand>[
        const AleraCommand(
          name: 'review',
          description: 'Review current changes',
          kind: AleraCommandKind.builtin,
          builtinId: BuiltinCommandId.review,
        ),
        const AleraCommand(
          name: 'revive',
          description: 'Revive an old branch',
          kind: AleraCommandKind.custom,
          scope: CustomCommandScope.repo,
          content: 'repo',
        ),
        const AleraCommand(
          name: 'release-version',
          description: 'Cut a release',
          kind: AleraCommandKind.custom,
          scope: CustomCommandScope.user,
          content: 'user',
        ),
      ];

      final filtered = registry.filter(commands, 'rev');

      expect(filtered.map((command) => command.name), <String>[
        'review',
        'revive',
        'release-version',
      ]);
    });

    test('matches description and argument hint when name does not match', () {
      final commands = <AleraCommand>[
        const AleraCommand(
          name: 'stacktrace',
          description: 'Debug a production incident',
          kind: AleraCommandKind.custom,
          scope: CustomCommandScope.repo,
          argumentHint: '<service>',
          content: 'repo',
        ),
      ];

      expect(registry.filter(commands, 'incident').single.name, 'stacktrace');
      expect(registry.filter(commands, 'service').single.name, 'stacktrace');
    });
  });

  group('CommandRegistry.findExact', () {
    const registry = CommandRegistry();

    test('matches command names case-insensitively', () {
      final command = registry.findExact(builtinAleraCommands(), 'ReViEw');
      expect(command?.builtinId, BuiltinCommandId.review);
    });
  });
}
