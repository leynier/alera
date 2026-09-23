import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_markdown_image_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/workspace_markdown_uri_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// An image a Markdown preview references. Remote http(s) images load
/// directly, workspace-relative ones through the paired runtime, and anything
/// else renders a placeholder.
class const WorkspaceMarkdownImage({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String markdownPath,
  required final String imageUrl,
  final double? width,
  final double? height,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isSupportedMarkdownViewerRemoteImageUri(Uri.tryParse(imageUrl))) {
      return Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: .contain,
        errorBuilder: (_, _, _) =>
            _MarkdownImagePlaceholder(width: width, height: height),
      );
    }
    final relativePath = resolveWorkspaceMarkdownImagePath(
      markdownPath: markdownPath,
      rawImageUrl: imageUrl,
    );
    if (relativePath == null) {
      return _MarkdownImagePlaceholder(width: width, height: height);
    }
    final image = ref.watch(
      workspaceMarkdownImageProvider(hostId, workspaceId, relativePath),
    );
    if (image.value case final bytes?) {
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: .contain,
        errorBuilder: (_, _, _) =>
            _MarkdownImagePlaceholder(width: width, height: height),
      );
    }
    return _MarkdownImagePlaceholder(
      width: width,
      height: height,
      loading: image.isLoading,
    );
  }
}

class const _MarkdownImagePlaceholder({
  final double? width,
  final double? height,
  final bool loading = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width ?? AleraTokens.space48,
      height: height ?? AleraTokens.space48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border.all(color: AleraTokens.borderSubtle),
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      ),
      child: loading
          ? const SizedBox.square(
              dimension: AleraTokens.space20,
              child: CircularProgressIndicator(
                strokeWidth: AleraTokens.strokeSm,
              ),
            )
          : const Icon(
              AleraIcons.imageError,
              color: AleraTokens.foregroundMuted,
              size: AleraTokens.space20,
            ),
    );
  }
}
