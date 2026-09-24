/// Explorer view choices the phone keeps per workspace.
///
/// Deliberately device-local, and a deliberate split from desktop. The
/// desktop's `explorerMode` and `sourceControlRootByWorkspaceId` live in its
/// `WorkbenchViewPrefs`, but `_sharedJson` in
/// `runtime_workbench_view_prefs_repository.dart` does not send either field to
/// the runtime, so neither is in `SharedWorkbenchViewPrefs` and there is no
/// shared record to read. Sharing them would mean widening that record, and a
/// desktop root is validated against the desktop filesystem, which a phone
/// cannot check. A nested root chosen on the phone therefore stays on the
/// phone.
class const ExplorerPreferences({
  final bool hideIgnored = true,
  final String? sourceControlRoot,
}) {
  factory fromJson(Map<String, Object?> json) {
    final root = json['sourceControlRoot'];
    return ExplorerPreferences(
      hideIgnored: json['hideIgnored'] != false,
      sourceControlRoot: root is String && root.trim().isNotEmpty
          ? root.trim()
          : null,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'hideIgnored': hideIgnored,
    if (sourceControlRoot != null) 'sourceControlRoot': sourceControlRoot,
  };

  ExplorerPreferences withHideIgnored(bool value) => ExplorerPreferences(
    hideIgnored: value,
    sourceControlRoot: sourceControlRoot,
  );

  ExplorerPreferences withSourceControlRoot(String? value) =>
      ExplorerPreferences(hideIgnored: hideIgnored, sourceControlRoot: value);

  @override
  bool operator ==(Object other) =>
      other is ExplorerPreferences &&
      other.hideIgnored == hideIgnored &&
      other.sourceControlRoot == sourceControlRoot;

  @override
  int get hashCode => Object.hash(hideIgnored, sourceControlRoot);
}
