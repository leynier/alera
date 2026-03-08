import 'dart:io';

import 'package:alera/src/features/session/domain/commands/alera_command.dart';
import 'package:path/path.dart' as p;

class CustomCommandRepository {
  const CustomCommandRepository({
    this.codexHomePath,
    this.homePath,
    this.environment,
  });

  final String? codexHomePath;
  final String? homePath;
  final Map<String, String>? environment;

  Future<List<AleraCommand>> discover({required String workspacePath}) async {
    final builtinNames = builtinAleraCommands()
        .map((command) => command.normalizedName)
        .toSet();
    final byName = <String, AleraCommand>{};
    for (final command in await _discoverInDirectory(
      _userPromptsDir(),
      scope: CustomCommandScope.user,
      excludeNames: builtinNames,
    )) {
      byName[command.name] = command;
    }
    for (final command in await _discoverInDirectory(
      p.join(workspacePath, '.codex', 'prompts'),
      scope: CustomCommandScope.repo,
      excludeNames: builtinNames,
    )) {
      byName[command.name] = command;
    }
    final commands = byName.values.toList(growable: false);
    commands.sort((a, b) => a.name.compareTo(b.name));
    return commands;
  }

  String _userPromptsDir() {
    if (codexHomePath != null && codexHomePath!.isNotEmpty) {
      return p.join(codexHomePath!, 'prompts');
    }
    final env = environment ?? Platform.environment;
    final codexHome = env['CODEX_HOME'];
    if (codexHome != null && codexHome.isNotEmpty) {
      return p.join(codexHome, 'prompts');
    }
    final home = homePath ?? env['HOME'];
    if (home == null || home.isEmpty) {
      return p.join('.codex', 'prompts');
    }
    return p.join(home, '.codex', 'prompts');
  }

  Future<List<AleraCommand>> _discoverInDirectory(
    String dirPath, {
    required CustomCommandScope scope,
    required Set<String> excludeNames,
  }) async {
    final directory = Directory(dirPath);
    if (!directory.existsSync()) {
      return const <AleraCommand>[];
    }
    final commands = <AleraCommand>[];
    await for (final entity in directory.list()) {
      if (entity is! File) {
        continue;
      }
      if (p.extension(entity.path).toLowerCase() != '.md') {
        continue;
      }
      final name = p.basenameWithoutExtension(entity.path);
      final normalizedName = name.trim().toLowerCase();
      if (!_isValidCustomCommandName(name) ||
          excludeNames.contains(normalizedName)) {
        continue;
      }
      String content;
      try {
        content = await entity.readAsString();
      } catch (_) {
        continue;
      }
      final parsed = parseCustomCommandFrontmatter(content);
      commands.add(
        AleraCommand(
          name: name,
          description: parsed.description ?? 'Run saved prompt',
          kind: AleraCommandKind.custom,
          scope: scope,
          content: parsed.body,
          argumentHint: parsed.argumentHint,
          supportsInlineArgs: true,
        ),
      );
    }
    commands.sort((a, b) => a.name.compareTo(b.name));
    return commands;
  }
}

class ParsedCustomCommandFrontmatter {
  const ParsedCustomCommandFrontmatter({
    required this.body,
    this.description,
    this.argumentHint,
  });

  final String body;
  final String? description;
  final String? argumentHint;
}

ParsedCustomCommandFrontmatter parseCustomCommandFrontmatter(String content) {
  final lines = content.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    return ParsedCustomCommandFrontmatter(body: content);
  }
  String? description;
  String? argumentHint;
  var closingIndex = -1;
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line == '---') {
      closingIndex = i;
      break;
    }
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final separator = line.indexOf(':');
    if (separator <= 0) {
      continue;
    }
    final key = line.substring(0, separator).trim().toLowerCase();
    final value = _stripQuotes(line.substring(separator + 1).trim());
    switch (key) {
      case 'description':
        description = value;
      case 'argument-hint':
      case 'argument_hint':
        argumentHint = value;
    }
  }
  if (closingIndex == -1) {
    return ParsedCustomCommandFrontmatter(body: content);
  }
  final body = lines.skip(closingIndex + 1).join('\n');
  return ParsedCustomCommandFrontmatter(
    body: body,
    description: description,
    argumentHint: argumentHint,
  );
}

String _stripQuotes(String value) {
  if (value.length >= 2) {
    final first = value[0];
    final last = value[value.length - 1];
    if ((first == '"' && last == '"') || (first == '\'' && last == '\'')) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}

bool _isValidCustomCommandName(String value) {
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(value);
}
