import 'package:alera/src/features/session/domain/commands/alera_command.dart';
import 'package:alera/src/features/session/domain/commands/custom_command_repository.dart';

class CommandRegistry {
  const CommandRegistry({
    this.customCommandRepository = const CustomCommandRepository(),
  });

  final CustomCommandRepository customCommandRepository;

  Future<List<AleraCommand>> loadForWorkspace(String workspacePath) async {
    final custom = await customCommandRepository.discover(
      workspacePath: workspacePath,
    );
    return <AleraCommand>[...builtinAleraCommands(), ...custom];
  }

  List<AleraCommand> filter(List<AleraCommand> commands, String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      final sorted = List<AleraCommand>.of(commands);
      sorted.sort(_compareCommands);
      return sorted;
    }
    final scored = commands
        .map((command) => (command: command, score: _score(command, trimmed)))
        .where((entry) => entry.score > 0)
        .toList(growable: false);
    scored.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return _compareCommands(left.command, right.command);
    });
    return scored.map((entry) => entry.command).toList(growable: false);
  }

  AleraCommand? findExact(List<AleraCommand> commands, String name) {
    final normalizedName = name.trim().toLowerCase();
    for (final command in commands) {
      if (command.normalizedName == normalizedName) {
        return command;
      }
    }
    return null;
  }

  int _compareCommands(AleraCommand left, AleraCommand right) {
    final kindCompare = _sourcePrecedence(
      left,
    ).compareTo(_sourcePrecedence(right));
    if (kindCompare != 0) {
      return kindCompare;
    }
    return left.normalizedName.compareTo(right.normalizedName);
  }

  int _sourcePrecedence(AleraCommand command) {
    if (command.isBuiltin) {
      return 0;
    }
    return switch (command.scope) {
      CustomCommandScope.repo => 1,
      CustomCommandScope.user => 2,
      null => 3,
    };
  }

  int _score(AleraCommand command, String query) {
    final normalizedQuery = query.toLowerCase();
    final sourceBonus = 30 - (_sourcePrecedence(command) * 10);
    final name = command.normalizedName;
    final description = command.description.toLowerCase();
    final argumentHint = (command.argumentHint ?? '').toLowerCase();

    if (name == normalizedQuery) {
      return 10000 + sourceBonus;
    }
    if (name.startsWith(normalizedQuery)) {
      return 8000 - (name.length - normalizedQuery.length) + sourceBonus;
    }
    final nameIndex = name.indexOf(normalizedQuery);
    if (nameIndex >= 0) {
      return 6000 - nameIndex + sourceBonus;
    }
    final subsequence = _subsequenceScore(name, normalizedQuery);
    if (subsequence > 0) {
      return 4000 + subsequence + sourceBonus;
    }
    final descriptionIndex = description.indexOf(normalizedQuery);
    if (descriptionIndex >= 0) {
      return 2000 - descriptionIndex + sourceBonus;
    }
    final hintIndex = argumentHint.indexOf(normalizedQuery);
    if (hintIndex >= 0) {
      return 1000 - hintIndex + sourceBonus;
    }
    return 0;
  }

  int _subsequenceScore(String haystack, String needle) {
    if (needle.isEmpty) {
      return 0;
    }
    var matched = 0;
    var gapPenalty = 0;
    for (var i = 0; i < haystack.length && matched < needle.length; i++) {
      if (haystack[i] == needle[matched]) {
        matched += 1;
        continue;
      }
      if (matched > 0) {
        gapPenalty += 1;
      }
    }
    if (matched != needle.length) {
      return 0;
    }
    return (needle.length * 20) - gapPenalty;
  }
}
