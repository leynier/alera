import 'package:alera/src/features/commands/application/slash_command_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SlashCommandRegistry', () {
    test('executes /init command', () async {
      final registry = SlashCommandRegistry();

      final execution = await registry.execute('/init set project rules');

      expect(execution, isNotNull);
      expect(execution!.metadata['command'], '/init');
      expect(execution.prompt, contains('Initialize the project context'));
    });

    test('executes /review command', () async {
      final registry = SlashCommandRegistry();

      final execution = await registry.execute('/review focus on tests');

      expect(execution, isNotNull);
      expect(execution!.metadata['command'], '/review');
      expect(execution.prompt, contains('Review current changes'));
    });

    test('returns null for unknown or non-command inputs', () async {
      final registry = SlashCommandRegistry();

      expect(await registry.execute('plain message'), isNull);
      expect(await registry.execute('/unknown something'), isNull);
    });
  });
}
