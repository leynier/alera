import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Terminal', group: 'Composer', size: Size(560, 180))
Widget aleraComposerPreview() => const _ComposerPreview();

class _ComposerPreview extends StatefulWidget {
  const _ComposerPreview();

  @override
  State<_ComposerPreview> createState() => _ComposerPreviewState();
}

class _ComposerPreviewState extends State<_ComposerPreview> {
  final _controller = TextEditingController(text: 'Summarize these changes');
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AleraComposer(
      controller: _controller,
      focusNode: _focusNode,
      onSend: _controller.clear,
      onClose: () {},
      textActions: const <AleraTextActionMenuItem>[
        AleraTextActionMenuItem(id: 'improve', label: 'Improve Writing'),
        AleraTextActionMenuItem(id: 'shorten', label: 'Make Concise'),
      ],
      onTextActionSelected: (_) {},
    );
  }
}
