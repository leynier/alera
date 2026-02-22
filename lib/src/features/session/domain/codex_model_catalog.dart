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

const String codexReasoningEffortLow = 'low';
const String codexReasoningEffortMedium = 'medium';
const String codexReasoningEffortHigh = 'high';
const String codexReasoningEffortXhigh = 'xhigh';

const List<String> codexReasoningEffortOrder = <String>[
  codexReasoningEffortLow,
  codexReasoningEffortMedium,
  codexReasoningEffortHigh,
  codexReasoningEffortXhigh,
];

const Map<String, String> codexReasoningEffortLabels = <String, String>{
  codexReasoningEffortLow: 'Low',
  codexReasoningEffortMedium: 'Medium',
  codexReasoningEffortHigh: 'High',
  codexReasoningEffortXhigh: 'Extra High',
};

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

const Map<String, List<String>> _modelReasoningEfforts = <String, List<String>>{
  'gpt-5.1-codex-mini': <String>[
    codexReasoningEffortMedium,
    codexReasoningEffortHigh,
  ],
};

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

String codexDefaultReasoningEffort() => codexReasoningEffortHigh;

bool codexReasoningEffortExists(String effort) {
  return codexReasoningEffortOrder.contains(effort);
}

String codexReasoningEffortLabel(String effort) {
  return codexReasoningEffortLabels[effort] ??
      codexReasoningEffortLabels[codexDefaultReasoningEffort()]!;
}

List<String> supportedReasoningEffortsForModel(String modelId) {
  return _modelReasoningEfforts[modelId] ?? codexReasoningEffortOrder;
}

bool isReasoningEffortSupported({
  required String modelId,
  required String effort,
}) {
  return supportedReasoningEffortsForModel(modelId).contains(effort);
}

String closestSupportedReasoningEffort({
  required String modelId,
  required String effort,
}) {
  final supported = supportedReasoningEffortsForModel(modelId);
  if (supported.isEmpty) {
    return codexDefaultReasoningEffort();
  }

  final normalizedTarget = codexReasoningEffortExists(effort)
      ? effort
      : codexDefaultReasoningEffort();
  if (supported.contains(normalizedTarget)) {
    return normalizedTarget;
  }

  final targetRank = _reasoningEffortRank(normalizedTarget);
  var closest = supported.first;
  var closestDistance = (_reasoningEffortRank(closest) - targetRank).abs();
  var closestRank = _reasoningEffortRank(closest);

  for (final candidate in supported.skip(1)) {
    final rank = _reasoningEffortRank(candidate);
    final distance = (rank - targetRank).abs();
    if (distance < closestDistance ||
        (distance == closestDistance && rank > closestRank)) {
      closest = candidate;
      closestDistance = distance;
      closestRank = rank;
    }
  }
  return closest;
}

int _reasoningEffortRank(String effort) {
  final index = codexReasoningEffortOrder.indexOf(effort);
  if (index == -1) {
    return codexReasoningEffortOrder.indexOf(codexDefaultReasoningEffort());
  }
  return index;
}
