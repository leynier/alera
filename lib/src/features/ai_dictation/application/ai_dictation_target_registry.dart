import 'package:flutter/material.dart';

class AiDictationTarget({
  required final String id,
  required final TextEditingController controller,
  required final FocusNode focusNode,
  final String? initialPrompt,
  final String? workspaceId,
  final String? tabId,
}) {
  bool insert(String text) {
    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    controller.value = value.copyWith(
      text: nextText,
      selection: .collapsed(offset: start + text.length),
      composing: .empty,
    );
    focusNode.requestFocus();
    return true;
  }
}

class AiDictationTargetRegistry {
  final Map<String, AiDictationTarget> _targets = <String, AiDictationTarget>{};

  String register({
    required TextEditingController controller,
    required FocusNode focusNode,
    String? initialPrompt,
    String? workspaceId,
    String? tabId,
  }) {
    final id =
        'dictation-target-${_targets.length}-${identityHashCode(controller)}';
    _targets[id] = AiDictationTarget(
      id: id,
      controller: controller,
      focusNode: focusNode,
      initialPrompt: initialPrompt,
      workspaceId: workspaceId,
      tabId: tabId,
    );
    return id;
  }

  void unregister(String id) => _targets.remove(id);

  AiDictationTarget? targetFor(String id) => _targets[id];

  String? targetForFocus() {
    for (final target in _targets.values) {
      if (target.focusNode.hasFocus) {
        return target.id;
      }
    }
    return null;
  }

  bool insert(String id, String text) => _targets[id]?.insert(text) ?? false;
}
