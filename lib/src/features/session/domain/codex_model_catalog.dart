class CodexModelOption {
  const CodexModelOption({
    required this.id,
    required this.label,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final bool isDefault;
}

const List<CodexModelOption> codexModelSnapshot = <CodexModelOption>[
  CodexModelOption(id: 'gpt-5.3-codex', label: 'GPT-5.3-Codex'),
  CodexModelOption(
    id: 'gpt-5.2-codex',
    label: 'GPT-5.2-Codex',
    isDefault: true,
  ),
  CodexModelOption(id: 'gpt-5.2', label: 'GPT-5.2'),
  CodexModelOption(id: 'gpt-5.1-codex-max', label: 'GPT-5.1-Codex-Max'),
  CodexModelOption(id: 'gpt-5.1-codex-mini', label: 'GPT-5.1-Codex-Mini'),
];

String codexDefaultModelId() {
  for (final model in codexModelSnapshot) {
    if (model.isDefault) {
      return model.id;
    }
  }
  return codexModelSnapshot.first.id;
}

bool codexModelExists(String id) {
  for (final model in codexModelSnapshot) {
    if (model.id == id) {
      return true;
    }
  }
  return false;
}
