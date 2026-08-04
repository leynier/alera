part of 'codex_chat_surface.dart';

extension _CodexDraftActions on _CodexChatSurfaceState {
  Future<void> _send(CodexChatController controller) async {
    final text = _expandSavedPrompt(_composer.text);
    final attachments = List<CodexInputAttachment>.of(_attachments);
    final draftItems = List<CodexDraftItem>.of(_draftItems);
    _composer.clear();
    _setSurfaceState(() {
      _attachments.clear();
      _draftItems.clear();
    });
    await controller.send(
      text,
      attachments: attachments,
      draftItems: draftItems,
    );
    if (mounted) _composerFocus.requestFocus();
  }

  void _editQueued(
    CodexChatController controller,
    int index,
    CodexQueuedMessage message,
  ) {
    if (_composer.text.isNotEmpty ||
        _attachments.isNotEmpty ||
        _draftItems.isNotEmpty) {
      AleraToast.show(
        context,
        message: 'Clear the current draft before editing a queued message.',
      );
      return;
    }
    controller.removeQueuedMessage(index);
    _composer.value = TextEditingValue(
      text: message.text,
      selection: TextSelection.collapsed(offset: message.text.length),
    );
    _setSurfaceState(() {
      _attachments
        ..clear()
        ..addAll(message.attachments);
      _draftItems
        ..clear()
        ..addAll(message.draftItems);
    });
    _composerFocus.requestFocus();
  }
}
