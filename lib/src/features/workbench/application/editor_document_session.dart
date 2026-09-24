part of 'workspace_file_service.dart';

class EditorDocumentSession({
  final VoidCallback? _onChanged,
  final bool Function()? _canEdit,
}) {
  /// Set when the file belongs to a remote workspace, so a save from a
  /// background path (Save All, close) routes to that host as well.
  Workspace? workspace;
  String? workspacePath;
  String? relativePath;
  String? loadedRawText;
  String? loadedText;
  String? currentText;
  String? contentToken;
  Object? loadError;
  WorkspaceEditorRevealTarget? pendingReveal;
  int tabSize = 4;

  bool get hasSnapshot => currentText != null || loadError != null;

  bool get canSave => loadedText != null && loadError == null;

  bool get isDirty => loadedText != null && currentText != loadedText;

  void attachFile({
    required String workspacePath,
    required String relativePath,
    Workspace? workspace,
  }) {
    this.workspace = workspace;
    if (this.workspacePath == workspacePath &&
        this.relativePath == relativePath) {
      return;
    }
    final changedCheckout =
        this.workspacePath != null && this.workspacePath != workspacePath;
    this.workspacePath = workspacePath;
    this.relativePath = relativePath;
    if (changedCheckout && !isDirty) {
      // Other clients can relocate this task without transferring our documents.
      clearSnapshot();
    } else {
      _notifyChanged();
    }
  }

  void acceptLoaded(native.WorkspaceEditorTextFile file, {int tabSize = 4}) {
    this.tabSize = tabSize;
    loadedRawText = file.rawContent;
    loadedText = file.displayContent;
    currentText = loadedText;
    contentToken = file.contentToken;
    loadError = null;
    _notifyChanged();
  }

  void acceptSaved(
    native.WorkspaceEditorTextFile file, {
    int? tabSize,
    String? preserveCurrentText,
  }) {
    acceptLoaded(file, tabSize: tabSize ?? this.tabSize);
    if (preserveCurrentText != null) {
      currentText = preserveCurrentText;
      _notifyChanged();
    }
  }

  void acceptLoadError(Object error) {
    loadedRawText = null;
    loadedText = null;
    currentText = null;
    contentToken = null;
    loadError = error;
    _notifyChanged();
  }

  void clearSnapshot() {
    loadedRawText = null;
    loadedText = null;
    currentText = null;
    contentToken = null;
    loadError = null;
    _notifyChanged();
  }

  void updateCurrentText(String text) {
    if (currentText == text || !(_canEdit?.call() ?? true)) {
      return;
    }
    currentText = text;
    _notifyChanged();
  }

  void _notifyChanged() {
    _onChanged?.call();
  }
}
