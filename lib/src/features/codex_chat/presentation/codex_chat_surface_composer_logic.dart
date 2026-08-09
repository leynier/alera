part of 'codex_chat_surface.dart';

// This part keeps stateful composer actions separate from the surface layout.
// ignore_for_file: invalid_use_of_protected_member

extension _CodexComposerLogic on _CodexComposerState {
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_disabled) return KeyEventResult.ignored;
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (Platform.isMacOS
            ? HardwareKeyboard.instance.isMetaPressed
            : HardwareKeyboard.instance.isControlPressed)) {
      unawaited(widget.onPaste());
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final overlayVisible =
        _commands.isNotEmpty ||
        _mentionFiles.isNotEmpty ||
        _catalogItems.isNotEmpty;
    if (!overlayVisible &&
        (event.logicalKey == LogicalKeyboardKey.arrowUp ||
            event.logicalKey == LogicalKeyboardKey.arrowDown) &&
        _navigatePromptHistory(event.logicalKey)) {
      return KeyEventResult.handled;
    }
    if (!overlayVisible) return KeyEventResult.ignored;
    final length = _commands.isNotEmpty
        ? _commands.length
        : _catalogItems.isNotEmpty
        ? _catalogItems.length
        : _mentionFiles.length;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selectedIndex = (_selectedIndex - 1).clamp(0, length - 1),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(
        () => _selectedIndex = (_selectedIndex + 1).clamp(0, length - 1),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clearOverlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_commands.isNotEmpty) {
        _selectCommand(_commands[_selectedIndex]);
      } else if (_catalogItems.isNotEmpty) {
        _selectCatalogItem(_catalogItems[_selectedIndex]);
      } else {
        _selectMention(_mentionFiles[_selectedIndex]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  TextRange? _replaceActive(RegExp pattern, String replacement) {
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0) return null;
    final before = widget.controller.text.substring(0, cursor);
    final match = pattern.firstMatch(before);
    if (match == null) return null;
    final after = widget.controller.text.substring(cursor);
    final next = '${before.substring(0, match.start)}$replacement$after';
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: match.start + replacement.length,
      ),
    );
    return TextRange(start: match.start, end: match.start + replacement.length);
  }

  void _selectMention(String path) {
    final token = codexFileReferenceText(path);
    final resolvedPath = p.isAbsolute(path)
        ? p.normalize(path)
        : p.normalize(p.join(widget.workspacePath, path));
    final duplicate = isCodexImagePath(path)
        ? widget.attachments.any(
            (attachment) =>
                p.equals(p.normalize(attachment.path), resolvedPath),
          )
        : widget.draftItems.any(
            (item) =>
                item.kind == CodexDraftItemKind.mention && item.path == path,
          );
    if (duplicate) {
      _replaceActive(RegExp(r'@\S*$'), '');
      _clearOverlay();
      return;
    }
    final inserted = _replaceActive(RegExp(r'@\S*$'), '$token ');
    if (inserted == null) {
      _clearOverlay();
      return;
    }
    if (isCodexImagePath(path)) {
      unawaited(
        widget.onDropAttachments(
          <String>[resolvedPath],
          origin: CodexInputAttachmentOrigin.mention,
          tokenText: token,
          tokenStart: inserted.start,
        ),
      );
      _clearOverlay();
      return;
    }
    widget.onDraftItemSelected(
      CodexDraftItem(
        id: 'mention-$path',
        kind: CodexDraftItemKind.mention,
        name: p.basename(path),
        path: path,
        tokenText: token,
        tokenStart: inserted.start,
      ),
    );
    _clearOverlay();
  }

  void _selectCommand(CodexComposerEntry entry) {
    _clearOverlay();
    final savedPrompt = entry.savedPrompt;
    if (savedPrompt != null) {
      _replaceActive(RegExp(r'^/\S*$'), '/${savedPrompt.name} ');
      return;
    }
    final command = entry.builtin!;
    if (command == CodexComposerCommand.rename) {
      _replaceActive(RegExp(r'^/\S*$'), '/rename ');
      return;
    }
    if (command == CodexComposerCommand.mention) {
      _replaceActive(RegExp(r'^/\S*$'), '@');
      return;
    }
    widget.controller.clear();
    widget.onCommand(command);
  }

  void _selectCatalogItem(CodexDraftItem item) {
    final duplicate = widget.draftItems.any(
      (existing) => existing.kind == item.kind && existing.path == item.path,
    );
    if (duplicate) {
      _replaceActive(RegExp(r'\$\S*$'), '');
      _clearOverlay();
      return;
    }
    final replaced = _replaceActive(
      RegExp(r'\$\S*$'),
      item.kind == CodexDraftItemKind.app ? '' : '\$${item.name} ',
    );
    if (replaced == null) {
      _clearOverlay();
      return;
    }
    widget.onDraftItemSelected(
      item.kind == CodexDraftItemKind.skill
          ? item.copyWith(tokenStart: replaced.start)
          : item,
    );
    _clearOverlay();
  }

  void _insertLineBreak() {
    final value = widget.controller.value;
    final start = value.selection.start < 0
        ? value.text.length
        : value.selection.start;
    final end = value.selection.end < 0
        ? value.text.length
        : value.selection.end;
    widget.controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  Widget _buildActionButton({required bool canSubmit}) {
    final isSendMode = _disabled || canSubmit || !widget.busy;
    final emphasized = !_disabled && (canSubmit || widget.busy);
    final VoidCallback? onPressed;
    final Widget icon;

    if (isSendMode) {
      onPressed = _disabled || widget.interrupting || !canSubmit
          ? null
          : widget.onSend;
      icon = const Icon(Icons.arrow_upward, size: AleraTokens.iconMd);
    } else if (widget.interrupting) {
      onPressed = null;
      icon = const RepaintBoundary(
        child: SizedBox.square(
          dimension: AleraTokens.iconMd,
          child: CircularProgressIndicator(
            strokeWidth: AleraTokens.strokeIndicator,
            color: AleraTokens.onAccent,
          ),
        ),
      );
    } else {
      onPressed = () => unawaited(widget.onStop());
      icon = const Icon(Icons.stop, size: AleraTokens.iconMd);
    }

    return IconButton(
      key: const ValueKey<String>('composer-action-button'),
      onPressed: onPressed,
      mouseCursor: SystemMouseCursors.click,
      constraints: const BoxConstraints.tightFor(
        width: AleraTokens.space24,
        height: AleraTokens.space24,
      ),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: emphasized
            ? AleraTokens.accent
            : AleraTokens.foregroundMuted,
        disabledBackgroundColor: emphasized
            ? AleraTokens.accent
            : AleraTokens.foregroundMuted,
        foregroundColor: emphasized
            ? AleraTokens.onAccent
            : AleraTokens.onAccent,
        disabledForegroundColor: emphasized
            ? AleraTokens.onAccent
            : AleraTokens.onAccent,
        minimumSize: const Size.square(AleraTokens.space24),
        maximumSize: const Size.square(AleraTokens.space24),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const CircleBorder(),
      ),
      icon: icon,
    );
  }
}
