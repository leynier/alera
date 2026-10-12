import 'package:alera/src/shared/infra/git/git_diff_models.dart';

class const GitWorkspaceComparison({
  required this.baseRef,
  required this.baseOid,
  required this.headOid,
  required this.headRef,
  required this.treeOid,
  required this.indexOid,
  required this.entries,
  required this.added,
  required this.removed,
}) {
  final String? baseRef;
  final String baseOid;
  final String? headOid;
  final String headRef;
  final String treeOid;
  final String indexOid;
  final List<GitChangeEntry> entries;
  final int added;
  final int removed;

  Map<String, Object?> toJson() => {
    'baseRef': baseRef,
    'baseOid': baseOid,
    'headOid': headOid,
    'headRef': headRef,
    'treeOid': treeOid,
    'indexOid': indexOid,
    'added': added,
    'removed': removed,
    'entries': [
      for (final entry in entries)
        {
          'path': entry.path,
          'oldPath': entry.oldPath,
          'area': entry.area.name,
          'status': entry.status.name,
          'added': entry.added,
          'removed': entry.removed,
          'isBinary': entry.isBinary,
          'isLarge': entry.isLarge,
          'submodule': null,
        },
    ],
  };

  factory fromJson(Map<String, Object?> json) => GitWorkspaceComparison(
    baseRef: json['baseRef'] as String?,
    baseOid: json['baseOid'] as String,
    headOid: json['headOid'] as String?,
    headRef: json['headRef'] as String,
    treeOid: json['treeOid'] as String,
    indexOid: json['indexOid'] as String,
    added: (json['added'] as num).toInt(),
    removed: (json['removed'] as num).toInt(),
    entries: List.unmodifiableOf(
      (json['entries'] as List).map((value) {
        final entry = Map<String, Object?>.from(value as Map);
        return GitChangeEntry(
          path: entry['path'] as String,
          oldPath: entry['oldPath'] as String?,
          area: GitChangeArea.values.byName(entry['area'] as String),
          status: GitChangeStatus.values.byName(entry['status'] as String),
          added: (entry['added'] as num?)?.toInt(),
          removed: (entry['removed'] as num?)?.toInt(),
          isBinary: entry['isBinary'] == true,
          isLarge: entry['isLarge'] == true,
        );
      }),
    ),
  );
}
