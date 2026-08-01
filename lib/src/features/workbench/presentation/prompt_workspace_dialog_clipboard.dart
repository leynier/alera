part of 'prompt_workspace_dialog.dart';

extension _PromptWorkspaceDialogClipboard on _PromptWorkspaceDialogState {
  Future<bool> _pastePromptClipboard() async {
    String? clipboardText;
    try {
      clipboardText = await widget.clipboard.readText();
    } catch (_) {
      // Image-only clipboards can reject text reads on some platforms.
    }
    if (clipboardText != null && clipboardText.isNotEmpty) {
      return false;
    }
    try {
      final imagePath = await widget.clipboard.saveImageAsTempFile();
      if (!mounted || imagePath == null || imagePath.isEmpty) {
        return false;
      }
      final value = _promptController.value;
      final selection = _validPromptSelection(value);
      _promptController.value = value.replaced(
        selection,
        sanitizeTerminalImagePastePath(imagePath),
      );
      _update(() => _error = null);
      return true;
    } catch (_) {
      if (mounted) {
        _update(() => _error = 'Could Not Paste Clipboard Image.');
      }
      return true;
    }
  }

  TextSelection _validPromptSelection(TextEditingValue value) {
    final selection = value.selection;
    if (selection.isValid &&
        selection.start <= value.text.length &&
        selection.end <= value.text.length) {
      return selection;
    }
    return TextSelection.collapsed(offset: value.text.length);
  }
}
