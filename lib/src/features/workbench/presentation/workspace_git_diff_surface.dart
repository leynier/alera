import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkspaceGitDiffSurface extends ConsumerStatefulWidget {
  const WorkspaceGitDiffSurface({
    super.key,
    required this.workspace,
    required this.tab,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;

  @override
  ConsumerState<WorkspaceGitDiffSurface> createState() =>
      _WorkspaceGitDiffSurfaceState();
}

class _WorkspaceGitDiffSurfaceState
    extends ConsumerState<WorkspaceGitDiffSurface> {
  Future<GitDiffResult>? _future;
  GitDiffResult? _loadedResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkspaceGitDiffSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.path != widget.workspace.path ||
        oldWidget.tab.id != widget.tab.id ||
        oldWidget.tab.payload != widget.tab.payload) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filePath = widget.tab.filePath;
    return DecoratedBox(
      decoration: const BoxDecoration(color: AleraTokens.bg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _GitDiffBar(
            title: widget.tab.title,
            filePath: filePath,
            onRefresh: _load,
            onOpenFile: _canOpenFile ? () => unawaited(_openFile()) : null,
          ),
          const Divider(height: 1, color: AleraTokens.borderSubtle),
          Expanded(
            child: FutureBuilder<GitDiffResult>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const _DiffMessage(message: 'Could not load diff.');
                }
                final result = snapshot.data;
                if (result == null || result.files.isEmpty) {
                  return const _DiffMessage(message: 'No diff available.');
                }
                return _DiffFileList(result: result);
              },
            ),
          ),
        ],
      ),
    );
  }

  bool get _canOpenFile {
    return _openableDiffFile != null;
  }

  GitDiffFile? get _openableDiffFile {
    final scope = widget.tab.gitDiffScope;
    if (widget.tab.filePath == null || scope == WorkspaceGitDiffScope.all) {
      return null;
    }
    final result = _loadedResult;
    if (result == null || result.files.isEmpty) {
      return null;
    }
    for (final file in result.files) {
      if (_isOpenableDiffFile(file)) {
        return file;
      }
    }
    return null;
  }

  bool _isOpenableDiffFile(GitDiffFile file) {
    if (file.status == GitChangeStatus.deleted) {
      return false;
    }
    if (file.status == GitChangeStatus.renamed && file.oldPath == file.path) {
      return false;
    }
    return true;
  }

  void _load() {
    final backend = ref.read(gitBackendProvider);
    final scope = widget.tab.gitDiffScope;
    final filePath = widget.tab.filePath;
    final area = widget.tab.gitDiffArea;
    final nextFuture = switch (scope) {
      WorkspaceGitDiffScope.all => backend.diffAll(path: widget.workspace.path),
      WorkspaceGitDiffScope.fileAll => backend.diffAll(
        path: widget.workspace.path,
        filePath: filePath,
      ),
      WorkspaceGitDiffScope.file =>
        filePath == null || area == null
            ? Future<GitDiffResult>.value(const GitDiffResult(files: []))
            : backend.diff(
                path: widget.workspace.path,
                filePath: filePath,
                area: area,
              ),
      null => Future<GitDiffResult>.value(const GitDiffResult(files: [])),
    };
    setState(() {
      _loadedResult = null;
      _future = nextFuture;
    });
    unawaited(
      nextFuture.then(
        (result) {
          if (!mounted || _future != nextFuture) {
            return;
          }
          setState(() {
            _loadedResult = result;
          });
        },
        onError: (_) {
          if (!mounted || _future != nextFuture) {
            return;
          }
          setState(() {
            _loadedResult = null;
          });
        },
      ),
    );
  }

  Future<void> _openFile() {
    final file = _openableDiffFile;
    if (file == null) {
      return Future<void>.value();
    }
    return ref
        .read(workbenchControllerProvider.notifier)
        .openEditorTab(workspace: widget.workspace, relativePath: file.path);
  }
}

class _GitDiffBar extends StatelessWidget {
  const _GitDiffBar({
    required this.title,
    required this.filePath,
    required this.onRefresh,
    required this.onOpenFile,
  });

  final String title;
  final String? filePath;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenFile;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            AleraFileIcon(
              pathOrName: filePath ?? title,
              kind: AleraFileIconKind.file,
              size: 16,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            AleraIconButton(
              tooltip: onOpenFile == null
                  ? 'File is not available in working tree'
                  : 'Open file',
              icon: AleraIcons.external,
              onPressed: onOpenFile,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Refresh',
              icon: AleraIcons.refresh,
              onPressed: onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _DiffFileList extends StatelessWidget {
  const _DiffFileList({required this.result});

  final GitDiffResult result;

  @override
  Widget build(BuildContext context) {
    final rows = _DiffRows.fromResult(result);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AleraTokens.space16),
      itemCount: rows.items.length,
      itemBuilder: (context, index) => rows.items[index].build(context),
    );
  }
}

class _DiffRows {
  const _DiffRows(this.items);

  final List<_DiffRow> items;

  factory _DiffRows.fromResult(GitDiffResult result) {
    final items = <_DiffRow>[
      if (result.truncated) const _BannerRow('Diff truncated for preview.'),
    ];
    for (final file in result.files) {
      items.add(_FileHeaderRow(file));
      if (file.isBinary) {
        items.add(const _BannerRow('Binary file diff is not shown.'));
      } else if (file.isLarge) {
        items.add(const _BannerRow('Large untracked file diff is not shown.'));
      } else if (file.lines.isEmpty) {
        items.add(const _BannerRow('No text diff for this file.'));
      } else {
        for (final line in file.lines) {
          items.add(_DiffLineRow(line));
        }
        if (file.linePreviewTruncated) {
          items.add(const _BannerRow('Diff line preview truncated.'));
        }
      }
      if (file.truncated) {
        items.add(const _BannerRow('File diff truncated for preview.'));
      }
    }
    return _DiffRows(items);
  }
}

abstract class _DiffRow {
  const _DiffRow();

  Widget build(BuildContext context);
}

class _FileHeaderRow extends _DiffRow {
  const _FileHeaderRow(this.file);

  final GitDiffFile file;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space8,
        ),
        child: Row(
          children: <Widget>[
            AleraFileIcon(
              pathOrName: file.path,
              kind: AleraFileIconKind.file,
              size: 16,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                '${file.area.label} · ${file.path}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontFamily: 'JetBrains Mono',
                ),
              ),
            ),
            _DiffStats(file: file),
          ],
        ),
      ),
    );
  }
}

class _BannerRow extends _DiffRow {
  const _BannerRow(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => _DiffBanner(message: message);
}

class _DiffLineRow extends _DiffRow {
  const _DiffLineRow(this.text);

  final GitDiffLine text;

  @override
  Widget build(BuildContext context) => _DiffLine(line: text);
}

class _DiffStats extends StatelessWidget {
  const _DiffStats({required this.file});

  final GitDiffFile file;

  @override
  Widget build(BuildContext context) {
    final visibleAdded = file.added != null && file.added! > 0
        ? file.added
        : null;
    final visibleRemoved = file.removed != null && file.removed! > 0
        ? file.removed
        : null;
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (visibleAdded case final added?)
          Text('+$added', style: style?.copyWith(color: AleraTokens.success)),
        if (visibleRemoved case final removed?) ...<Widget>[
          const SizedBox(width: AleraTokens.space6),
          Text('-$removed', style: style?.copyWith(color: AleraTokens.error)),
        ],
      ],
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line});

  final GitDiffLine line;

  @override
  Widget build(BuildContext context) {
    final (color, background) = switch (line.kind) {
      GitDiffLineKind.addition => (
        AleraTokens.success,
        AleraTokens.success.withValues(alpha: 0.08),
      ),
      GitDiffLineKind.deletion => (
        AleraTokens.error,
        AleraTokens.error.withValues(alpha: 0.08),
      ),
      GitDiffLineKind.hunk => (AleraTokens.warning, AleraTokens.surfaceVariant),
      GitDiffLineKind.header || GitDiffLineKind.context => (
        AleraTokens.foregroundMuted,
        Colors.transparent,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: background),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space2,
        ),
        child: Text(
          line.text,
          maxLines: 1,
          overflow: TextOverflow.visible,
          softWrap: false,
          style: AleraTokens.monoStyle.copyWith(fontSize: 12, color: color),
        ),
      ),
    );
  }
}

class _DiffBanner extends StatelessWidget {
  const _DiffBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}

class _DiffMessage extends StatelessWidget {
  const _DiffMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}
