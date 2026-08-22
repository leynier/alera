part of 'mobile_codex_chat_screen.dart';

// The Quick Open sheet itself lives in `workspace_file_picker_sheet.dart` so the
// terminal composer can attach workspace files through the same UI. These
// aliases keep the many call sites in this library unchanged.

String _mobileBaseName(String path) => workspaceFileBaseName(path);

IconData _mobileFileIcon(String path) => workspaceFileIcon(path);

/// Ends a Quick Open session without letting a teardown failure surface: the
/// caller is already leaving the picker or the catalog.
Future<void> _stopMobileWorkspaceQuickOpen(
  MobileCodexController controller,
  MobileWorkspaceQuickOpenSession session,
) async {
  try {
    await controller.stopWorkspaceQuickOpen(session);
  } on Object catch (error, stackTrace) {
    _MobileCodexChatScreenState._logger.warning(
      'Could not stop a mobile Quick Open session.',
      error,
      stackTrace,
    );
  }
}
