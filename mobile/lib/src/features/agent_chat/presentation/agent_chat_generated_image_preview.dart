import 'dart:async';
import 'dart:typed_data';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_generated_images.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether [item] saved an image the timeline can show.
bool agentChatShowsGeneratedImage(AgentChatItem item) =>
    item.type == AgentChatItemType.imageGeneration &&
    !item.isInProgress &&
    !item.isFailed &&
    item.imagePath != null;

/// The image a completed `image_generation` item saved, under its row.
/// Tapping it opens it full screen; nothing shows while it loads or when
/// the host cannot serve it.
class const AgentChatGeneratedImagePreview({
  super.key,
  required final AgentChatItem item,
}) extends ConsumerWidget {
  static const double maxHeight = 280;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = AgentChatScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final image = ref
        .watch(
          agentChatGeneratedImageProvider(
            scope.hostId,
            scope.workspaceId,
            scope.chatId,
            item.id,
          ),
        )
        .value;
    if (image == null) return const SizedBox.shrink();
    final pixels = (maxHeight * MediaQuery.devicePixelRatioOf(context)).round();
    return Padding(
      padding: const EdgeInsets.only(
        left: AleraTokens.space24,
        bottom: AleraTokens.space8,
      ),
      child: Semantics(
        button: true,
        label: 'Generated image, open full screen',
        child: GestureDetector(
          key: ValueKey<String>('agent-chat-generated-image-${item.id}'),
          onTap: () => unawaited(_showFullScreen(context, image.bytes)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: maxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
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
    );
  }

  static Future<void> _showFullScreen(BuildContext context, Uint8List bytes) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (context) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: const Text('Generated Image'),
            ),
            body: InteractiveViewer(
              maxScale: 6,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
          ),
        ),
      );
}
