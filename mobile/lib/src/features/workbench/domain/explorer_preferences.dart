/// Explorer view choices the phone keeps per workspace.
///
/// They stay on the device rather than in the host's shared view prefs: the
/// desktop keeps its own explorer mode and Source Control root locally too, so
/// sharing them would make the two surfaces overwrite each other.
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
