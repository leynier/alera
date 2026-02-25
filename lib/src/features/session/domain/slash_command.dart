enum SlashCommandKind { clearInput, insertText }

class SlashCommandDef {
  const SlashCommandDef({
    required this.name,
    required this.description,
    this.kind = SlashCommandKind.insertText,
    this.insertText,
  });

  final String name;
  final String description;
  final SlashCommandKind kind;
  // Text inserted into the composer when kind == insertText.
  final String? insertText;
}

const List<SlashCommandDef> builtinSlashCommands = <SlashCommandDef>[
  SlashCommandDef(
    name: 'clear',
    description: 'Clear the input field',
    kind: SlashCommandKind.clearInput,
  ),
  SlashCommandDef(
    name: 'review',
    description: 'Ask the agent to review code changes',
    kind: SlashCommandKind.insertText,
    insertText: 'Please review the recent code changes and provide feedback.',
  ),
  SlashCommandDef(
    name: 'commit',
    description: 'Ask the agent to commit staged changes',
    kind: SlashCommandKind.insertText,
    insertText: 'Please commit the staged changes with an appropriate message.',
  ),
  SlashCommandDef(
    name: 'test',
    description: 'Ask the agent to run tests',
    kind: SlashCommandKind.insertText,
    insertText: 'Please run the tests and report any failures.',
  ),
  SlashCommandDef(
    name: 'explain',
    description: 'Ask the agent to explain the current code',
    kind: SlashCommandKind.insertText,
    insertText: 'Please explain what the current code does.',
  ),
  SlashCommandDef(
    name: 'fix',
    description: 'Ask the agent to fix errors or issues',
    kind: SlashCommandKind.insertText,
    insertText: 'Please identify and fix any errors or issues.',
  ),
];

List<SlashCommandDef> filterSlashCommands(String query) {
  if (query.isEmpty) {
    return builtinSlashCommands;
  }
  final lower = query.toLowerCase();
  return builtinSlashCommands
      .where(
        (cmd) =>
            cmd.name.toLowerCase().contains(lower) ||
            cmd.description.toLowerCase().contains(lower),
      )
      .toList(growable: false);
}
