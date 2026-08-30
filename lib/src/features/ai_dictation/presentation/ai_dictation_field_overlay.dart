import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_control.dart';
import 'package:alera/src/features/ai_dictation/presentation/ai_dictation_target.dart';
import 'package:flutter/material.dart';

class const AiDictationFieldOverlay({
  super.key,
  required final TextEditingController controller,
  required final FocusNode focusNode,
  required final Widget child,
  final String? initialPrompt,
  final Key? controlKey,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AiDictationTarget(
      controller: controller,
      focusNode: focusNode,
      initialPrompt: initialPrompt,
      builder: (context, targetId) => Stack(
        children: <Widget>[
          child,
          Positioned(
            top: AleraTokens.space8,
            right: AleraTokens.space8,
            child: AiDictationControl(
              key: controlKey,
              targetId: targetId,
              enabled: enabled,
            ),
          ),
        ],
      ),
    );
  }
}
