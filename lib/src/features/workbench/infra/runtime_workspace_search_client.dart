import 'package:alera/src/features/workbench/application/workspace_search_service.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/rust/api/workspace_search.dart' as native;

const Duration _searchTimeout = Duration(minutes: 2);
const Duration _cancelTimeout = Duration(seconds: 30);

/// Runs Find and Replace in Files for a remote workspace through the runtime,
/// which forwards the `mobile.workspaceSearch.*` verbs to the owning host.
/// The wire shape is the same one the phone reads, so the two never disagree
/// on match ids or content tokens.
class RuntimeWorkspaceSearchClient implements WorkspaceSearchService {
  RuntimeWorkspaceSearchClient(
    this._client, {
    required this.workspaceId,
    this.beforeAccess,
  });

  final RuntimeHostClient _client;
  final String workspaceId;
  final Future<void> Function()? beforeAccess;

  @override
  Future<native.WorkspaceSearchResult> search({
    required native.WorkspaceSearchOptions options,
    required String requestId,
  }) async {
    final payload = await _request('mobile.workspaceSearch.run', {
      ..._searchFields(options),
      'requestId': requestId,
    }, _searchTimeout);
    return searchResultFromRuntimeJson(payload);
  }

  @override
  Future<native.WorkspaceReplacePreview> previewReplace({
    required native.WorkspaceReplaceOptions options,
    required String requestId,
  }) async {
    final payload = await _request('mobile.workspaceSearch.run', {
      ..._searchFields(options.search),
      'replacement': options.replacement,
      'preserveCase': options.preserveCase,
      'requestId': requestId,
    }, _searchTimeout);
    return native.WorkspaceReplacePreview(
      result: searchResultFromRuntimeJson(payload),
      replacement: options.replacement,
      preserveCase: options.preserveCase,
    );
  }

  @override
  Future<void> cancel({required String requestId}) async {
    try {
      await beforeAccess?.call();
      await _client.runtimeRequest('mobile.workspaceSearch.cancel', {
        'requestId': requestId,
      }, _cancelTimeout);
    } catch (_) {
      // Cancellation is best effort; a late result is dropped by generation.
    }
  }

  @override
  Future<native.WorkspaceReplaceResult> replaceMatches({
    required native.WorkspaceReplaceRequest request,
  }) async {
    final payload = await _request('mobile.workspaceSearch.replace', {
      ..._searchFields(request.options.search),
      'replacement': request.options.replacement,
      'preserveCase': request.options.preserveCase,
      'matchIds': request.matchIds,
      'expectedFiles': <Object?>[
        for (final file in request.expectedFiles)
          <String, Object?>{
            'relativePath': file.relativePath,
            'contentToken': file.contentToken,
          },
      ],
    }, _searchTimeout);
    return replaceResultFromRuntimeJson(payload);
  }

  Map<String, Object?> _searchFields(native.WorkspaceSearchOptions options) {
    final include = options.includePattern?.trim();
    final exclude = options.excludePattern?.trim();
    return <String, Object?>{
      'workspaceId': workspaceId,
      'query': options.query,
      'caseSensitive': options.caseSensitive,
      'wholeWord': options.wholeWord,
      'useRegex': options.useRegex,
      'includeIgnored': options.includeIgnored,
      if (include != null && include.isNotEmpty) 'includePattern': include,
      if (exclude != null && exclude.isNotEmpty) 'excludePattern': exclude,
    };
  }

  Future<Map<String, Object?>> _request(
    String type,
    Map<String, Object?> payload,
    Duration timeout,
  ) async {
    try {
      await beforeAccess?.call();
      return _asMap(await _client.runtimeRequest(type, payload, timeout));
    } catch (error) {
      throw WorkspaceException(userFacingExceptionMessage(error));
    }
  }
}

native.WorkspaceSearchResult searchResultFromRuntimeJson(
  Map<String, Object?> payload,
) {
  final files = <native.WorkspaceSearchFileResult>[];
  final rawFiles = payload['files'];
  if (rawFiles is List) {
    for (final rawFile in rawFiles) {
      final file = _asMap(rawFile);
      final matches = <native.WorkspaceSearchMatch>[];
      final rawMatches = file['matches'];
      if (rawMatches is List) {
        for (final rawMatch in rawMatches) {
          final match = _asMap(rawMatch);
          matches.add(
            native.WorkspaceSearchMatch(
              id: _string(match['id']),
              line: _int(match['line']),
              column: _int(match['column']),
              matchLength: _int(match['matchLength']),
              lineContent: _string(match['lineContent']),
              displayColumn: _optionalInt(match['displayColumn']),
              displayMatchLength: _optionalInt(match['displayMatchLength']),
              replacementPreview: match['replacementPreview'] as String?,
            ),
          );
        }
      }
      files.add(
        native.WorkspaceSearchFileResult(
          relativePath: _string(file['relativePath']),
          contentToken: _string(file['contentToken']),
          matches: matches,
        ),
      );
    }
  }
  return native.WorkspaceSearchResult(
    files: files,
    totalMatches: _int(payload['totalMatches']),
    truncated: payload['truncated'] == true,
  );
}

native.WorkspaceReplaceResult replaceResultFromRuntimeJson(
  Map<String, Object?> payload,
) {
  final conflicts = <native.WorkspaceReplaceConflict>[];
  final rawConflicts = payload['conflicts'];
  if (rawConflicts is List) {
    for (final rawConflict in rawConflicts) {
      final conflict = _asMap(rawConflict);
      conflicts.add(
        native.WorkspaceReplaceConflict(
          relativePath: _string(conflict['relativePath']),
          reason: _string(conflict['reason']),
        ),
      );
    }
  }
  return native.WorkspaceReplaceResult(
    filesChanged: _int(payload['filesChanged']),
    matchesReplaced: _int(payload['matchesReplaced']),
    conflicts: conflicts,
  );
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw const FormatException(
    'Runtime workspace search payload must be a JSON object.',
  );
}

String _string(Object? value) => value is String ? value : '';

int _int(Object? value) => value is num ? value.toInt() : 0;

int? _optionalInt(Object? value) => value is num ? value.toInt() : null;
