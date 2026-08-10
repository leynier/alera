import 'package:alera/src/features/ai_dictation/application/ai_dictation_providers.dart';
import 'package:alera/src/features/ai_dictation/application/ai_dictation_target_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiDictationTarget extends StatefulWidget {
  const AiDictationTarget({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.builder,
    this.initialPrompt,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? initialPrompt;
  final Widget Function(BuildContext context, String targetId) builder;

  @override
  State<AiDictationTarget> createState() => _AiDictationTargetState();
}

class _AiDictationTargetState extends State<AiDictationTarget> {
  late String _targetId;
  AiDictationTargetRegistry? _registry;

  @override
  void initState() {
    super.initState();
    _registry = _tryRegistry(context);
    _targetId =
        _registry?.register(
          controller: widget.controller,
          focusNode: widget.focusNode,
          initialPrompt: widget.initialPrompt,
        ) ??
        'dictation-target-${identityHashCode(widget.controller)}';
  }

  @override
  void didUpdateWidget(covariant AiDictationTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.focusNode != widget.focusNode ||
        oldWidget.initialPrompt != widget.initialPrompt) {
      final registry = _registry ??= _tryRegistry(context);
      registry?.unregister(_targetId);
      _targetId =
          registry?.register(
            controller: widget.controller,
            focusNode: widget.focusNode,
            initialPrompt: widget.initialPrompt,
          ) ??
          'dictation-target-${identityHashCode(widget.controller)}';
    }
  }

  @override
  void dispose() {
    _registry?.unregister(_targetId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _targetId);

  AiDictationTargetRegistry? _tryRegistry(BuildContext context) {
    try {
      return ProviderScope.containerOf(
        context,
        listen: false,
      ).read(aiDictationTargetRegistryProvider);
    } on StateError {
      return null;
    }
  }
}
