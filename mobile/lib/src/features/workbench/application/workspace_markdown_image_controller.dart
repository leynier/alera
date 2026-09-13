import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_markdown_image_controller.g.dart';

final Logger _logger = Logger('WorkspaceMarkdownImage');

/// Bytes of a workspace image that a Markdown preview references, read through
/// the paired runtime. Null when the file is not an image, is larger than
/// [maxMobileMarkdownImageBytes], or cannot be read.
@riverpod
Future<Uint8List?> workspaceMarkdownImage(
  Ref ref,
  String hostId,
  String workspaceId,
  String relativePath,
) async {
  final client = await ref.watch(workspaceClientProvider(hostId).future);
  if (client is! MobileCodexWorkspaceClient) {
    return null;
  }
  final files = client as MobileCodexWorkspaceClient;
  try {
    final bytes = BytesBuilder(copy: false);
    var offset = 0;
    while (true) {
      final range = await files.readWorkspaceFile(
        workspaceId: workspaceId,
        relativePath: relativePath,
        offset: offset,
      );
      if (!range.mimeType.startsWith('image/') ||
          range.totalBytes > maxMobileMarkdownImageBytes) {
        return null;
      }
      bytes.add(range.bytes);
      if (range.nextOffset >= range.totalBytes || range.nextOffset <= offset) {
        break;
      }
      offset = range.nextOffset;
    }
    return bytes.takeBytes();
  } on Object catch (error, stackTrace) {
    _logger.warning('Could not load a Markdown image.', error, stackTrace);
    return null;
  }
}
