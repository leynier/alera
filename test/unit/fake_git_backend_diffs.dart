part of 'fake_git_backend.dart';

mixin _FakeGitBackendDiffs {
  List<GitBackendCall> get calls;

  GitDiffResult gitDiffResult = const GitDiffResult(files: []);
  GitDiffResult gitDiffAllResult = const GitDiffResult(files: []);
  Uint8List readingDiffPatchResult = Uint8List(0);
  GitException? readingDiffPatchError;

  /// Bytes served by [diffBlobBytes], keyed by file path and requested side.
  final Map<({String filePath, bool oldSide}), Uint8List> diffBlobBytesBySide =
      <({String filePath, bool oldSide}), Uint8List>{};

  Future<GitDiffResult> diff({
    required String path,
    required String filePath,
    required GitChangeArea area,
  }) async {
    calls.add(
      GitBackendCall('diff', <String, Object?>{
        'path': path,
        'filePath': filePath,
        'area': area,
      }),
    );
    return gitDiffResult;
  }

  Future<GitDiffResult> diffAll({
    required String path,
    String? filePath,
  }) async {
    calls.add(
      GitBackendCall('diffAll', <String, Object?>{
        'path': path,
        'filePath': filePath,
      }),
    );
    return gitDiffAllResult;
  }

  Future<Uint8List> readingDiffPatch({
    required String path,
    String? filePath,
    String? oldPath,
    GitChangeArea? area,
    String? commitOid,
    String? parentOid,
    String? baseRef,
  }) async {
    calls.add(
      GitBackendCall('readingDiffPatch', <String, Object?>{
        'path': path,
        'filePath': filePath,
        'oldPath': oldPath,
        'area': area,
        'commitOid': commitOid,
        'parentOid': parentOid,
        'baseRef': baseRef,
      }),
    );
    final error = readingDiffPatchError;
    if (error != null) {
      throw error;
    }
    return readingDiffPatchResult;
  }

  Future<Uint8List?> diffBlobBytes({
    required String path,
    required String filePath,
    String? oldPath,
    GitChangeArea? area,
    String? commitOid,
    String? parentOid,
    required bool oldSide,
  }) async {
    calls.add(
      GitBackendCall('diffBlobBytes', <String, Object?>{
        'path': path,
        'filePath': filePath,
        'oldPath': oldPath,
        'area': area,
        'commitOid': commitOid,
        'parentOid': parentOid,
        'oldSide': oldSide,
      }),
    );
    return diffBlobBytesBySide[(filePath: filePath, oldSide: oldSide)];
  }
}
