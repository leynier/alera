class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.description,
    required this.handler,
  });

  final String name;
  final String description;
  final Future<SlashCommandExecution> Function(String args) handler;
}

class SlashCommandExecution {
  const SlashCommandExecution({
    required this.prompt,
    this.metadata = const <String, dynamic>{},
  });

  final String prompt;
  final Map<String, dynamic> metadata;
}
