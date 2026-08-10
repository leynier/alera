import 'package:alera/src/features/ai_dictation/application/ai_dictation_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiDictationTarget extends ConsumerStatefulWidget {
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
  ConsumerState<AiDictationTarget> createState() => _AiDictationTargetState();
}

class _AiDictationTargetState extends ConsumerState<AiDictationTarget> {
  late String _targetId;

  @override
  void initState() {
    super.initState();
    _targetId = ref
        .read(aiDictationTargetRegistryProvider)
        .register(
          controller: widget.controller,
          focusNode: widget.focusNode,
          initialPrompt: widget.initialPrompt,
        );
  }

  @override
  void didUpdateWidget(covariant AiDictationTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.focusNode != widget.focusNode ||
        oldWidget.initialPrompt != widget.initialPrompt) {
      final registry = ref.read(aiDictationTargetRegistryProvider);
      registry.unregister(_targetId);
      _targetId = registry.register(
        controller: widget.controller,
        focusNode: widget.focusNode,
        initialPrompt: widget.initialPrompt,
      );
    }
  }

  @override
  void dispose() {
    ref.read(aiDictationTargetRegistryProvider).unregister(_targetId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _targetId);
}
