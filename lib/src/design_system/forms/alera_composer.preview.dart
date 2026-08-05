import 'package:alera/src/design_system/alera_preview.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

@AleraPreview(name: 'Terminal', group: 'Composer', size: Size(560, 220))
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
      hasAttachments: true,
      attachmentBar: const _PreviewAttachmentBar(),
      textActions: const <AleraTextActionMenuItem>[
        AleraTextActionMenuItem(id: 'improve', label: 'Improve Writing'),
        AleraTextActionMenuItem(id: 'shorten', label: 'Make Concise'),
      ],
      onTextActionSelected: (_) {},
    );
  }
}

class _PreviewAttachmentBar extends StatelessWidget {
  const _PreviewAttachmentBar();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space8,
        AleraTokens.space8,
        AleraTokens.space8,
        0,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          height: AleraTokens.space32,
          decoration: BoxDecoration(
            color: AleraTokens.surface,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: AleraTokens.space32,
                child: Icon(
                  AleraIcons.imageError,
                  size: AleraTokens.space16,
                  color: AleraTokens.foregroundFaint,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AleraTokens.space6),
                child: Text('terminal-screenshot.png'),
              ),
              Padding(
                padding: EdgeInsets.all(AleraTokens.space6),
                child: Icon(
                  AleraIcons.close,
                  size: AleraTokens.space12,
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
