part of 'github_forge_provider.dart';

mixin _GitHubCliRunner {
  ProcessRunner get _processRunner;

  /// Runs a read `gh` command expected to emit JSON on stdout. Throws a typed
  /// [ForgeException] on failure. When [allowNotFound] is set, a not-found
  /// result yields null instead of throwing.
  Future<String?> _run(
    List<String> arguments,
    String repoPath, {
    bool allowNotFound = false,
  }) async {
    ProcessRunOutput result;
    try {
      result = await _processRunner.run(
        'gh',
        arguments,
        workingDirectory: repoPath,
      );
    } catch (_) {
      throw const ForgeCliMissing('gh not found');
    }
    if (result.exitCode == 0) {
      return result.stdout;
    }
    if (ghLooksLikeMissingCli(result)) {
      throw const ForgeCliMissing('gh not found');
    }
    if (allowNotFound && _mentionsNotFound(result.stderr)) {
      return null;
    }
    _throwClassified(result);
  }

  Never _throwClassified(ProcessRunOutput result) {
    final stderr = result.stderr.trim();
    final lower = stderr.toLowerCase();
    if (lower.contains('not logged') ||
        lower.contains('authentication') ||
        lower.contains('gh auth login')) {
      throw ForgeNotAuthenticated(stderr);
    }
    final disallowed = mapGitHubDisallowedMergeMethodMessage(stderr);
    if (disallowed != null) {
      throw ForgeRequestFailed(disallowed);
    }
    throw ForgeRequestFailed(stderr.isEmpty ? 'gh command failed' : stderr);
  }

  Object? _decodeJson(String? raw) {
    if (raw == null) {
      return null;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final decoded = _tryDecode(trimmed);
    if (decoded == null) {
      throw ForgeRequestFailed('Unexpected gh output: $trimmed');
    }
    return decoded;
  }

  Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  bool _mentionsNoChecks(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('no checks') || lower.contains('no check runs');
  }

  bool _mentionsNotFound(String stderr) {
    final lower = stderr.toLowerCase();
    return lower.contains('no pull requests found') ||
        lower.contains('not found') ||
        lower.contains('could not resolve');
  }

  int? _pullNumberFromUrl(String output) {
    final url = _firstUrl(output);
    if (url == null) {
      return null;
    }
    final match = RegExp(r'/pull/(\d+)').firstMatch(url);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  String? _firstUrl(String output) {
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('http')) {
        return trimmed;
      }
    }
    return null;
  }
}
