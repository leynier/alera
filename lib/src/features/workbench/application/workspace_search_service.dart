import 'package:alera/src/rust/api/workspace_search.dart' as native;

class const WorkspaceSearchService() {
  Future<native.WorkspaceSearchResult> search({
    required native.WorkspaceSearchOptions options,
    required String requestId,
  }) {
    return native.searchWorkspaceCancelable(
      options: options,
      requestId: requestId,
    );
  }

  Future<native.WorkspaceReplacePreview> previewReplace({
    required native.WorkspaceReplaceOptions options,
    required String requestId,
  }) {
    return native.previewWorkspaceReplaceCancelable(
      options: options,
      requestId: requestId,
    );
  }

  Future<void> cancel({required String requestId}) =>
      native.cancelWorkspaceSearch(requestId: requestId);

  Future<native.WorkspaceReplaceResult> replaceMatches({
    required native.WorkspaceReplaceRequest request,
  }) {
    return native.replaceWorkspaceMatches(request: request);
  }
}
