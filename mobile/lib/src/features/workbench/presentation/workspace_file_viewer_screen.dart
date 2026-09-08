import 'dart:convert';
import 'dart:typed_data';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_codex_workspace.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const WorkspaceFileViewerScreen({
  super.key,
  required final String hostId,
  required final String workspaceId,
  required final String relativePath,
  this.highlightLine,
}) extends ConsumerStatefulWidget {
  final int? highlightLine;

  @override
  ConsumerState<WorkspaceFileViewerScreen> createState() =>
      _WorkspaceFileViewerScreenState();
}

class _WorkspaceFileViewerScreenState
    extends ConsumerState<WorkspaceFileViewerScreen> {
  late final Future<MobileWorkspaceFileRange> _load = _read();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<MobileWorkspaceFileRange> _read() async {
    final client = await ref.read(
      workspaceClientProvider(widget.hostId).future,
    );
    if (client case final MobileCodexWorkspaceClient files) {
      return files.readWorkspaceFile(
        workspaceId: widget.workspaceId,
        relativePath: widget.relativePath,
      );
    }
    throw UnsupportedError(
      'Update the paired Alera runtime to preview workspace files.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          workspaceFileBaseName(widget.relativePath),
          overflow: .ellipsis,
        ),
      ),
      body: FutureBuilder<MobileWorkspaceFileRange>(
        future: _load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: AleraTokens.contentPadding,
                child: Text(snapshot.error.toString(), textAlign: .center),
              ),
            );
          }
          final range = snapshot.data;
          if (range == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _FileBody(
            range: range,
            highlightLine: widget.highlightLine,
            scrollController: _scroll,
          );
        },
      ),
    );
  }
}

class const _FileBody({
  required final MobileWorkspaceFileRange range,
  required final ScrollController scrollController,
  final int? highlightLine,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (range.mimeType.startsWith('image/') && range.bytes.isNotEmpty) {
      return Center(
        child: Image.memory(Uint8List.fromList(range.bytes), fit: .contain),
      );
    }
    if (!range.isText) {
      return AleraEmptyState(
        icon: AleraIcons.files,
        message:
            'This file cannot be previewed on the phone (${range.mimeType}).',
      );
    }
    final text = utf8.decode(range.bytes, allowMalformed: true);
    final lines = text.split('\n');
    final truncated = range.nextOffset < range.totalBytes;
    return Column(
      children: <Widget>[
        if (truncated)
          Material(
            color: AleraTokens.surfaceElevated,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space16,
                vertical: AleraTokens.space8,
              ),
              child: Text(
                'Showing the first ${range.bytes.length} bytes of ${range.totalBytes}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            padding: AleraTokens.contentPadding,
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final selected =
                  highlightLine != null && highlightLine == index + 1;
              return ColoredBox(
                color: selected ? AleraTokens.accentSubtle : Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AleraTokens.space2,
                  ),
                  child: Text(
                    '${index + 1}  ${lines[index]}',
                    style: AleraTokens.monoStyle.copyWith(
                      color: selected
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
