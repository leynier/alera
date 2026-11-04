import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_generated_images.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The image a completed `image_generation` item saved, under its row.
/// Clicking it opens the file; nothing shows while it loads or when the
/// host cannot serve it.
class const AgentChatGeneratedImagePreview({
  super.key,
  required final AgentChatRef chat,
  required final AgentChatItem item,
  required final ValueChanged<String> onOpenFile,
}) extends ConsumerWidget {
  static const double maxHeight = 360;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = item.imagePath;
    final image = ref
        .watch(
          agentChatGeneratedImageProvider(
            chat.chatId,
            chat.workspaceId,
            item.id,
          ),
        )
        .value;
    if (path == null || image == null) return const SizedBox.shrink();
    final pixels = (maxHeight * MediaQuery.devicePixelRatioOf(context)).round();
    return Padding(
      padding: const EdgeInsets.only(
        left: AleraTokens.space24,
        top: AleraTokens.space2,
        bottom: AleraTokens.space6,
      ),
      child: Semantics(
        button: true,
        label: 'Generated image, open ${item.imagePath}',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: ValueKey<String>('agent-chat-generated-image-${item.id}'),
            onTap: () => onOpenFile(path),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: maxHeight),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                child: Image(
                  image: ResizeImage(
                    MemoryImage(image.bytes),
                    height: pixels,
                    policy: ResizeImagePolicy.fit,
                  ),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
