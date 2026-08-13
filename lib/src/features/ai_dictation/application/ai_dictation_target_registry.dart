import 'package:flutter/material.dart';

class AiDictationTarget {
  AiDictationTarget({
    required this.id,
    required this.controller,
    required this.focusNode,
    this.initialPrompt,
  });

  final String id;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? initialPrompt;

  bool insert(String text) {
    final value = controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, text);
    controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + text.length),
      composing: TextRange.empty,
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
  }) {
    final id =
        'dictation-target-${_targets.length}-${identityHashCode(controller)}';
    _targets[id] = AiDictationTarget(
      id: id,
      controller: controller,
      focusNode: focusNode,
      initialPrompt: initialPrompt,
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
