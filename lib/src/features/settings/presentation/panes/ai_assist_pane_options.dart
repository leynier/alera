part of 'ai_assist_pane.dart';

extension on _AiAssistSettingsPaneState {
  AiAssistSettings _updateGlobalThinking(
    AiAssistSettings settings,
    String model,
    String? value,
  ) {
    final selected = <String, String>{...settings.selectedThinkingByModel};
    if (value == null) {
      selected.remove(model);
    } else {
      selected[model] = value;
    }
    return settings.copyWith(selectedThinkingByModel: selected);
  }

  AiAssistSettings _updateOperationThinking(
    AiAssistSettings settings,
    AiAssistOperation operation,
    String model,
    String? value,
  ) {
    final selected = <AiAssistOperation, Map<String, String>>{
      ...settings.selectedThinkingByOperation,
    };
    final operationValues = <String, String>{
      ...selected[operation] ?? const <String, String>{},
    };
    if (value == null) {
      operationValues.remove(model);
    } else {
      operationValues[model] = value;
    }
    if (operationValues.isEmpty) {
      selected.remove(operation);
    } else {
      selected[operation] = operationValues;
    }
    return settings.copyWith(selectedThinkingByOperation: selected);
  }

  bool _usesChatGpt(AiAssistSettings settings) {
    return settings.agent == AiAssistAgent.chatgpt ||
        settings.promptSettingsByOperation.values.any(
          (prompt) => prompt.agent == AiAssistAgent.chatgpt,
        );
  }
}
