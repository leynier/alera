part of 'terminal_runtime.dart';

void _handleTerminalPrivateOsc(
  _XtermTerminalSessionHandle handle,
  String code,
  List<String> args,
) {
  if (code == '52') {
    final request = parseTerminalOsc52Request(args);
    if (request is! TerminalOsc52Write) {
      return;
    }
    if (!handle._settings.allowOsc52Clipboard) {
      handle._osc52Blocked();
      return;
    }
    unawaited(
      handle._clipboard.writeText(request.text).catchError((Object error) {
        handle._notifyInteraction(
          'Could Not Copy Terminal Selection.',
          error: true,
        );
      }),
    );
    return;
  }
  handle._osc8LinkTracker.handlePrivateOsc(code, args);
}

Future<void> _pasteTerminalClipboard(_XtermTerminalSessionHandle handle) async {
  String? text;
  try {
    text = await handle._clipboard.readText();
  } catch (_) {
    // Image-only clipboards can reject text-flavor reads on some platforms.
  }
  if (handle._disposed) {
    return;
  }
  if (text != null && text.isNotEmpty) {
    handle._terminal.paste(text);
    return;
  }
  try {
    final imagePath = await handle._clipboard.saveImageAsTempFile();
    if (handle._disposed || imagePath == null || imagePath.isEmpty) {
      return;
    }
    // Shell quoting would corrupt the generated path for at least one of
    // POSIX, PowerShell, cmd, or the foreground TUI. Let the terminal apply
    // bracketed paste only when the foreground program enabled DECSET 2004.
    handle._terminal.paste(sanitizeTerminalImagePastePath(imagePath));
  } catch (error) {
    handle._notifyInteraction('Could Not Paste Clipboard Image.', error: true);
  }
}

void _handleTerminalSelectionChanged(_XtermTerminalSessionHandle handle) {
  handle._selectionCopyTimer?.cancel();
  handle._selectionCopyTimer = null;
  if (handle._disposed || !handle._settings.clipboardOnSelect) {
    return;
  }
  final selection = handle._terminalController.selection;
  if (selection == null) {
    return;
  }
  handle._selectionCopyTimer = Timer(const Duration(milliseconds: 100), () {
    if (handle._disposed || !handle._settings.clipboardOnSelect) {
      return;
    }
    final currentSelection = handle._terminalController.selection;
    if (currentSelection == null) {
      return;
    }
    final text = handle._terminal.buffer.getText(currentSelection);
    if (text.isEmpty) {
      return;
    }
    unawaited(
      handle._clipboard.writeText(text).catchError((Object error) {
        handle._notifyInteraction(
          'Could Not Copy Terminal Selection.',
          error: true,
        );
      }),
    );
  });
}

void _publishTerminalInteraction(
  _XtermTerminalSessionHandle handle,
  String message, {
  required bool error,
}) {
  handle._interactionNotice?.call(message, error: error);
}

xterm.Terminal _createSessionTerminal(_XtermTerminalSessionHandle handle) {
  return xterm.Terminal(
    maxLines: handle._settings.scrollbackLines,
    platform: _xtermTargetPlatform,
    wordSeparators: _wordSeparatorsFromSettings(
      handle._settings.wordSeparators,
    ),
  );
}

void _attachSessionTerminal(
  _XtermTerminalSessionHandle handle,
  xterm.Terminal terminal,
) {
  terminal.onTitleChange = handle._handleTitleChanged;
  terminal.onOutput = handle._handleTerminalInput;
  terminal.onResize = handle._handleTerminalResize;
  terminal.onPrivateOSC = handle._handlePrivateOsc;
}

void _detachSessionTerminal(xterm.Terminal terminal) {
  terminal.onTitleChange = null;
  terminal.onOutput = null;
  terminal.onResize = null;
  terminal.onPrivateOSC = null;
}
