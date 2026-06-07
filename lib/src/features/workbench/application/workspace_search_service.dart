import 'package:alera/src/rust/api/workspace_search.dart' as native;

class WorkspaceSearchService {
  const WorkspaceSearchService();

  Future<native.WorkspaceSearchResult> search({
    required native.WorkspaceSearchOptions options,
  }) {
    return native.searchWorkspace(options: options);
  }

  Future<native.WorkspaceReplacePreview> previewReplace({
    required native.WorkspaceReplaceOptions options,
  }) {
    return native.previewWorkspaceReplace(options: options);
  }

  Future<native.WorkspaceReplaceResult> replaceMatches({
    required native.WorkspaceReplaceRequest request,
  }) {
    return native.replaceWorkspaceMatches(request: request);
  }
}
