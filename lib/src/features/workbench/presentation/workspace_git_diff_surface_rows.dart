part of 'workspace_git_diff_surface.dart';

class _DiffFileList extends StatelessWidget {
  const _DiffFileList({
    required this.result,
    required this.sourcePath,
    this.sourceLabel,
    this.commitOid,
    this.parentOid,
  });

  final GitDiffResult result;
  final String sourcePath;
  final String? sourceLabel;
  final String? commitOid;
  final String? parentOid;

  @override
  Widget build(BuildContext context) {
    final rows = _DiffRows.fromResult(
      result,
      sourcePath: sourcePath,
      sourceLabel: sourceLabel,
      commitOid: commitOid,
      parentOid: parentOid,
    );
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

  factory _DiffRows.fromResult(
    GitDiffResult result, {
    required String sourcePath,
    String? sourceLabel,
    String? commitOid,
    String? parentOid,
  }) {
    final items = <_DiffRow>[
      if (result.truncated) const _BannerRow('Diff truncated for preview.'),
    ];
    for (final file in result.files) {
      items.add(_FileHeaderRow(file, sourceLabel: sourceLabel));
      if (file.isBinary && isWorkspaceImageFilePath(file.path)) {
        items.add(
          _ImageDiffRow(
            file: file,
            sourcePath: sourcePath,
            commitOid: commitOid,
            parentOid: parentOid,
          ),
        );
      } else if (file.isBinary) {
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
  const _FileHeaderRow(this.file, {this.sourceLabel});

  final GitDiffFile file;
  final String? sourceLabel;

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
                '${sourceLabel ?? file.sourceLabel ?? file.area.label} · ${file.path}',
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

class _ImageDiffRow extends _DiffRow {
  const _ImageDiffRow({
    required this.file,
    required this.sourcePath,
    this.commitOid,
    this.parentOid,
  });

  final GitDiffFile file;
  final String sourcePath;
  final String? commitOid;
  final String? parentOid;

  @override
  Widget build(BuildContext context) => WorkspaceGitDiffImageRow(
    file: file,
    sourcePath: sourcePath,
    commitOid: commitOid,
    parentOid: parentOid,
  );
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
