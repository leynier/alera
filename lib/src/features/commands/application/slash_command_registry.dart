import 'package:alera/src/features/commands/domain/slash_command.dart';

class SlashCommandRegistry {
  SlashCommandRegistry() {
    register(
      SlashCommand(
        name: '/init',
        description: 'Initialize project context and coding conventions.',
        handler: (args) async => SlashCommandExecution(
          prompt: 'Initialize the project context. $args',
          metadata: const <String, dynamic>{'command': '/init'},
        ),
      ),
    );

    register(
      SlashCommand(
        name: '/review',
        description: 'Run a focused code review on current changes.',
        handler: (args) async => SlashCommandExecution(
          prompt: 'Review current changes and list findings by severity. $args',
          metadata: const <String, dynamic>{'command': '/review'},
        ),
      ),
    );
  }

  final Map<String, SlashCommand> _commands = <String, SlashCommand>{};

  void register(SlashCommand command) {
    _commands[command.name] = command;
  }

  Iterable<SlashCommand> list() => _commands.values;

  Future<SlashCommandExecution?> execute(String rawInput) async {
    final input = rawInput.trim();
    if (!input.startsWith('/')) {
      return null;
    }

    final split = input.split(' ');
    final name = split.first;
    final args = split.length > 1 ? input.substring(name.length).trim() : '';

    final command = _commands[name];
    if (command == null) {
      return null;
    }

    return command.handler(args);
  }
}
