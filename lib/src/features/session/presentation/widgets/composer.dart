import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/commands/alera_command.dart';
import 'package:alera/src/features/session/domain/commands/command_parser.dart';
import 'package:alera/src/features/session/domain/commands/command_registry.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/domain/composer_draft_item.dart';
import 'package:alera/src/features/session/domain/context_usage.dart';
import 'package:alera/src/features/session/domain/pending_approval.dart';
import 'package:alera/src/features/session/presentation/widgets/attachment_bar.dart';
import 'package:alera/src/features/session/presentation/widgets/composer_draft_item_bar.dart';
import 'package:alera/src/features/session/presentation/widgets/context_usage_indicator.dart';
import 'package:alera/src/features/session/presentation/widgets/mention_file_list.dart';
import 'package:alera/src/features/session/presentation/widgets/slash_command_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.textFieldEnabled,
    required this.canSend,
    required this.canStop,
    required this.canChangeModel,
    required this.isBusy,
    required this.isInterrupting,
    required this.activeModelId,
    required this.availableModels,
    required this.onModelChanged,
    required this.activeReasoningEffort,
    required this.supportedReasoningEfforts,
    required this.onReasoningEffortChanged,
    required this.onSend,
    required this.onInterrupt,
    this.hintText = 'Ask for follow-up changes',
    this.attachments = const <ComposerAttachment>[],
    this.draftItems = const <ComposerDraftItem>[],
    this.availableCommands = const <AleraCommand>[],
    this.onAddAttachment,
    this.onPasteImage,
    this.onRemoveAttachment,
    this.onRemoveDraftItem,
    this.onImmediateCommandSelected,
    this.workspacePath,
    this.planModeEnabled = false,
    this.onPlanModeToggled,
    this.permissionMode = PermissionMode.defaultMode,
    this.onPermissionModeSelected,
    this.focusNode,
    this.contextUsage,
    this.onCompact,
  });

  final TextEditingController controller;
  final bool textFieldEnabled;
  final bool canSend;
  final bool canStop;
  final bool canChangeModel;
  final bool isBusy;
  final bool isInterrupting;
  final String activeModelId;
  final List<CodexModelOption> availableModels;
  final ValueChanged<String> onModelChanged;
  final String activeReasoningEffort;
  final List<String> supportedReasoningEfforts;
  final ValueChanged<String> onReasoningEffortChanged;
  final VoidCallback onSend;
  final VoidCallback onInterrupt;
  final String hintText;
  final List<ComposerAttachment> attachments;
  final List<ComposerDraftItem> draftItems;
  final List<AleraCommand> availableCommands;
  final VoidCallback? onAddAttachment;
  final ValueChanged<File>? onPasteImage;
  final ValueChanged<String>? onRemoveAttachment;
  final ValueChanged<String>? onRemoveDraftItem;
  final ValueChanged<AleraCommand>? onImmediateCommandSelected;
  final String? workspacePath;
  final bool planModeEnabled;
  final VoidCallback? onPlanModeToggled;
  final PermissionMode permissionMode;
  final ValueChanged<PermissionMode>? onPermissionModeSelected;
  final FocusNode? focusNode;
  final ContextUsage? contextUsage;
  final VoidCallback? onCompact;

  @override
  State<Composer> createState() => ComposerState();
}

class ComposerState extends State<Composer> {
  late final FocusNode _focusNode;
  final GlobalKey<PopupMenuButtonState<String>> _modelMenuKey =
      GlobalKey<PopupMenuButtonState<String>>();
  final GlobalKey<PopupMenuButtonState<String>> _reasoningMenuKey =
      GlobalKey<PopupMenuButtonState<String>>();
  final GlobalKey<PopupMenuButtonState<PermissionMode>> _permissionMenuKey =
      GlobalKey<PopupMenuButtonState<PermissionMode>>();
  final CommandRegistry _commandRegistry = const CommandRegistry();
  List<String> _mentionFiles = const <String>[];
  int _mentionSelectedIndex = 0;
  Timer? _mentionDebounce;
  List<AleraCommand> _slashCommands = const <AleraCommand>[];
  int _slashSelectedIndex = 0;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.onKeyEvent = _handleKeyEvent;
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _mentionDebounce?.cancel();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void requestFocus() {
    _focusNode.requestFocus();
  }

  void openModelsDropdown() {
    _modelMenuKey.currentState?.showButtonMenu();
  }

  void openReasoningDropdown() {
    _reasoningMenuKey.currentState?.showButtonMenu();
  }

  void openPermissionDropdown() {
    _permissionMenuKey.currentState?.showButtonMenu();
  }

  String _shortcutHint(String modifier) {
    return Platform.isMacOS ? '⌘$modifier' : 'Ctrl+$modifier';
  }

  String get _activeModelLabel {
    for (final model in widget.availableModels) {
      if (model.id == widget.activeModelId) {
        return model.label;
      }
    }
    return widget.activeModelId;
  }

  String get _reasoningLabel =>
      codexReasoningEffortLabel(widget.activeReasoningEffort);

  String get _permissionLabel {
    switch (widget.permissionMode) {
      case PermissionMode.defaultMode:
        return 'Ask first';
      case PermissionMode.fullAccess:
        return 'Full access';
    }
  }

  bool get _hasOverlay => _mentionFiles.isNotEmpty || _slashCommands.isNotEmpty;

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (Platform.isMacOS
            ? HardwareKeyboard.instance.isMetaPressed
            : HardwareKeyboard.instance.isControlPressed)) {
      _tryPasteImage();
      return KeyEventResult.ignored;
    }

    if (!_hasOverlay || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (_slashCommands.isNotEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _slashSelectedIndex = (_slashSelectedIndex - 1).clamp(
            0,
            _slashCommands.length - 1,
          );
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _slashSelectedIndex = (_slashSelectedIndex + 1).clamp(
            0,
            _slashCommands.length - 1,
          );
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_slashSelectedIndex < _slashCommands.length) {
          _selectSlashCommand(_slashCommands[_slashSelectedIndex]);
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _clearSlash();
        return KeyEventResult.handled;
      }
    }
    if (_mentionFiles.isNotEmpty) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _mentionSelectedIndex = (_mentionSelectedIndex - 1).clamp(
            0,
            _mentionFiles.length - 1,
          );
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _mentionSelectedIndex = (_mentionSelectedIndex + 1).clamp(
            0,
            _mentionFiles.length - 1,
          );
        });
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_mentionSelectedIndex < _mentionFiles.length) {
          _selectMention(_mentionFiles[_mentionSelectedIndex]);
        }
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _clearMention();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onControllerChanged() {
    final newHasText = widget.controller.text.isNotEmpty;
    if (newHasText != _hasText) {
      setState(() {
        _hasText = newHasText;
      });
    }
    _mentionDebounce?.cancel();
    _mentionDebounce = Timer(
      const Duration(milliseconds: 120),
      _updateMentionState,
    );
  }

  void _updateMentionState() {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0) {
      _clearMention();
      _clearSlash();
      return;
    }
    if (looksLikeSlashQuery(text, cursor)) {
      _clearMention();
      final query = extractSlashQuery(text, cursor);
      final filtered = _commandRegistry.filter(widget.availableCommands, query);
      setState(() {
        _slashCommands = filtered;
        _slashSelectedIndex = 0;
      });
      return;
    }
    _clearSlash();
    final beforeCursor = text.substring(0, cursor);
    final mentionMatch = RegExp(r'@(\S*)$').firstMatch(beforeCursor);
    if (mentionMatch == null) {
      _clearMention();
      return;
    }
    final query = mentionMatch.group(1) ?? '';
    _fetchMentionFiles(query);
  }

  void _clearMention() {
    if (_mentionFiles.isNotEmpty) {
      setState(() {
        _mentionFiles = const <String>[];
        _mentionSelectedIndex = 0;
      });
    }
  }

  void _clearSlash() {
    if (_slashCommands.isNotEmpty) {
      setState(() {
        _slashCommands = const <AleraCommand>[];
        _slashSelectedIndex = 0;
      });
    }
  }

  void _selectSlashCommand(AleraCommand command) {
    if (_requiresInlineCommandInput(command)) {
      final insertion = command.supportsInlineArgs || command.isCustom
          ? '/${command.name} '
          : '/${command.name}';
      _replaceActiveSlashQuery(insertion);
      _clearSlash();
      return;
    }
    if (command.builtinId == BuiltinCommandId.mention) {
      _replaceActiveSlashQuery('@');
      _clearSlash();
      return;
    }
    widget.controller.clear();
    _clearSlash();
    widget.onImmediateCommandSelected?.call(command);
  }

  bool _requiresInlineCommandInput(AleraCommand command) {
    if (command.isCustom) {
      return true;
    }
    return command.builtinId == BuiltinCommandId.rename;
  }

  void _replaceActiveSlashQuery(String replacement) {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0) {
      return;
    }
    final beforeCursor = text.substring(0, cursor);
    final match = RegExp(r'^/\S*$').firstMatch(beforeCursor);
    if (match == null) {
      return;
    }
    final afterCursor = text.substring(cursor);
    final newText =
        '${beforeCursor.substring(0, match.start)}$replacement$afterCursor';
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: match.start + replacement.length,
      ),
      composing: TextRange.empty,
    );
  }

  Future<void> _fetchMentionFiles(String query) async {
    final workspacePath = widget.workspacePath;
    if (workspacePath == null || workspacePath.isEmpty) {
      _clearMention();
      return;
    }
    final ProcessResult result;
    try {
      result = await Process.run('git', <String>[
        'ls-files',
      ], workingDirectory: workspacePath);
    } catch (_) {
      _clearMention();
      return;
    }
    if (!mounted) {
      return;
    }
    if (result.exitCode != 0) {
      _clearMention();
      return;
    }
    final all = (result.stdout as String)
        .split('\n')
        .where((f) => f.isNotEmpty)
        .toList();
    final filtered = query.isEmpty
        ? all.take(20).toList(growable: false)
        : all
              .where((f) => f.toLowerCase().contains(query.toLowerCase()))
              .take(20)
              .toList(growable: false);
    setState(() {
      _mentionFiles = filtered;
      _mentionSelectedIndex = 0;
    });
  }

  void _selectMention(String relativePath) {
    final text = widget.controller.text;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0) {
      return;
    }
    final beforeCursor = text.substring(0, cursor);
    final match = RegExp(r'@\S*$').firstMatch(beforeCursor);
    if (match == null) {
      return;
    }
    final afterCursor = text.substring(cursor);
    final newText =
        '${beforeCursor.substring(0, match.start)}@$relativePath $afterCursor';
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: match.start + relativePath.length + 2,
      ),
      composing: TextRange.empty,
    );
    _clearMention();
  }

  Future<void> _tryPasteImage() async {
    final callback = widget.onPasteImage;
    if (callback == null) {
      return;
    }
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) {
        return;
      }
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/alera_paste_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(bytes);
      callback(tempFile);
    } catch (_) {
      // Ignore clipboard failures.
    }
  }

  void _sendFromShortcut() {
    if (!widget.canSend) {
      return;
    }
    widget.onSend();
  }

  void _insertLineBreak() {
    if (!widget.textFieldEnabled) {
      return;
    }
    final value = widget.controller.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;
    final nextText = value.text.replaceRange(start, end, '\n');
    widget.controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  Widget _buildActionButton() {
    final isSendMode = _hasText || !widget.canStop;
    final VoidCallback? onPressed;
    final Widget icon;

    if (isSendMode) {
      onPressed = widget.canSend ? widget.onSend : null;
      icon = const Icon(Icons.arrow_upward, size: 16);
    } else if (widget.isInterrupting) {
      onPressed = null;
      icon = const RepaintBoundary(
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: AleraTokens.onAccent,
          ),
        ),
      );
    } else {
      onPressed = widget.onInterrupt;
      icon = const Icon(Icons.stop, size: 18);
    }

    return IconButton(
      key: const ValueKey<String>('composer-send-stop-button'),
      onPressed: onPressed,
      mouseCursor: SystemMouseCursors.click,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        backgroundColor: (widget.canSend || widget.canStop)
            ? AleraTokens.accent
            : AleraTokens.surface,
        foregroundColor: (widget.canSend || widget.canStop)
            ? AleraTokens.onAccent
            : AleraTokens.foregroundFaint,
        shape: const CircleBorder(),
      ),
      icon: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasContextCompact =
        widget.contextUsage != null && widget.onCompact != null;
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        children: <Widget>[
          if (_slashCommands.isNotEmpty)
            SlashCommandList(
              commands: _slashCommands,
              selectedIndex: _slashSelectedIndex,
              onSelect: _selectSlashCommand,
            ),
          if (_mentionFiles.isNotEmpty)
            MentionFileList(
              files: _mentionFiles,
              selectedIndex: _mentionSelectedIndex,
              onSelect: _selectMention,
            ),
          if (widget.isBusy)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                child: const RepaintBoundary(
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    color: AleraTokens.accent,
                    backgroundColor: AleraTokens.surfaceVariant,
                  ),
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: AleraTokens.surfaceVariant,
              borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
              border: Border.all(color: AleraTokens.border),
            ),
            child: Stack(
              children: <Widget>[
                Column(
                  children: <Widget>[
                    if (widget.draftItems.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                          right: hasContextCompact ? 24.0 : 0.0,
                        ),
                        child: ComposerDraftItemBar(
                          items: widget.draftItems,
                          onRemove: widget.onRemoveDraftItem ?? (_) {},
                        ),
                      ),
                    if (widget.attachments.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                          right: hasContextCompact ? 24.0 : 0.0,
                        ),
                        child: AttachmentBar(
                          attachments: widget.attachments,
                          onRemove: widget.onRemoveAttachment ?? (_) {},
                        ),
                      ),
                    CallbackShortcuts(
                      bindings: <ShortcutActivator, VoidCallback>{
                        const SingleActivator(LogicalKeyboardKey.enter):
                            _sendFromShortcut,
                        const SingleActivator(
                          LogicalKeyboardKey.enter,
                          shift: true,
                        ): _insertLineBreak,
                      },
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        enabled: widget.textFieldEnabled,
                        minLines: 2,
                        maxLines: 6,
                        textInputAction: TextInputAction.newline,
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          filled: true,
                          fillColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          contentPadding: EdgeInsets.fromLTRB(
                            AleraTokens.space12,
                            AleraTokens.space16,
                            hasContextCompact ? 36.0 : AleraTokens.space12,
                            AleraTokens.space8,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AleraTokens.space8,
                        0,
                        AleraTokens.space8,
                        AleraTokens.space8,
                      ),
                      child: Row(
                        children: <Widget>[
                          IconButton(
                            onPressed: widget.onAddAttachment,
                            tooltip: 'Add photos & files',
                            mouseCursor: SystemMouseCursors.click,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                            padding: const EdgeInsets.all(AleraTokens.space4),
                            icon: Icon(
                              Icons.add,
                              size: 18,
                              color: widget.onAddAttachment != null
                                  ? AleraTokens.foregroundMuted
                                  : AleraTokens.foregroundFaint,
                            ),
                          ),
                          const SizedBox(width: AleraTokens.space4),
                          PopupMenuButton<String>(
                            key: _modelMenuKey,
                            tooltip: 'Choose model (${_shortcutHint('⇧M')})',
                            onSelected: widget.canChangeModel
                                ? widget.onModelChanged
                                : null,
                            enabled: widget.canChangeModel,
                            constraints: const BoxConstraints(minWidth: 220),
                            itemBuilder: (context) => <PopupMenuEntry<String>>[
                              const PopupMenuItem<String>(
                                enabled: false,
                                height: 32,
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  'Select model',
                                  style: TextStyle(
                                    color: AleraTokens.foregroundFaint,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              ...widget.availableModels.map(
                                (model) => DropdownEntry<String>(
                                  value: model.id,
                                  label: model.label,
                                  selected: model.id == widget.activeModelId,
                                ),
                              ),
                            ],
                            child: ComposerChip(label: _activeModelLabel),
                          ),
                          const SizedBox(width: AleraTokens.space6),
                          PopupMenuButton<String>(
                            key: _reasoningMenuKey,
                            tooltip:
                                'Select reasoning effort (${_shortcutHint('T')})',
                            onSelected: widget.canChangeModel
                                ? widget.onReasoningEffortChanged
                                : null,
                            enabled: widget.canChangeModel,
                            itemBuilder: (context) => <PopupMenuEntry<String>>[
                              const PopupMenuItem<String>(
                                enabled: false,
                                height: 32,
                                padding: EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  'Select reasoning effort',
                                  style: TextStyle(
                                    color: AleraTokens.foregroundFaint,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              ...widget.supportedReasoningEfforts.map(
                                (effort) => DropdownEntry<String>(
                                  value: effort,
                                  label: codexReasoningEffortLabel(effort),
                                  selected:
                                      effort == widget.activeReasoningEffort,
                                ),
                              ),
                            ],
                            child: ComposerChip(label: _reasoningLabel),
                          ),
                          const SizedBox(width: AleraTokens.space6),
                          Tooltip(
                            message:
                                'Toggle plan mode (${_shortcutHint('⇧P')})',
                            child: InkWell(
                              onTap: widget.onPlanModeToggled,
                              borderRadius: BorderRadius.circular(
                                AleraTokens.radiusLg,
                              ),
                              mouseCursor: SystemMouseCursors.click,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: widget.planModeEnabled
                                      ? AleraTokens.info.withValues(alpha: 0.14)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(
                                    AleraTokens.radiusLg,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AleraTokens.space8,
                                  vertical: AleraTokens.space4,
                                ),
                                child: Text(
                                  'Plan',
                                  style: TextStyle(
                                    color: widget.planModeEnabled
                                        ? AleraTokens.info
                                        : AleraTokens.foregroundFaint,
                                    fontSize: 12,
                                    fontWeight: widget.planModeEnabled
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AleraTokens.space6),
                          PopupMenuButton<PermissionMode>(
                            key: _permissionMenuKey,
                            tooltip:
                                'Choose approval mode (${_shortcutHint('⇧Y')})',
                            onSelected: widget.onPermissionModeSelected,
                            itemBuilder: (context) =>
                                <PopupMenuEntry<PermissionMode>>[
                                  const PopupMenuItem<PermissionMode>(
                                    enabled: false,
                                    height: 32,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      'Select approval mode',
                                      style: TextStyle(
                                        color: AleraTokens.foregroundFaint,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  DropdownEntry<PermissionMode>(
                                    value: PermissionMode.defaultMode,
                                    label: 'Ask first',
                                    selected:
                                        widget.permissionMode ==
                                        PermissionMode.defaultMode,
                                  ),
                                  DropdownEntry<PermissionMode>(
                                    value: PermissionMode.fullAccess,
                                    label: 'Full access',
                                    selected:
                                        widget.permissionMode ==
                                        PermissionMode.fullAccess,
                                  ),
                                ],
                            child: ComposerChip(
                              label: _permissionLabel,
                              highlight:
                                  widget.permissionMode ==
                                  PermissionMode.fullAccess,
                            ),
                          ),
                          const Spacer(),
                          _buildActionButton(),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hasContextCompact)
                  Positioned(
                    top: 10,
                    right: 12,
                    child: ContextUsageIndicator(
                      contextUsage: widget.contextUsage!,
                      onCompact: widget.onCompact!,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ComposerChip extends StatelessWidget {
  const ComposerChip({super.key, required this.label, this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final textColor = highlight
        ? AleraTokens.warning
        : AleraTokens.foregroundMuted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: TextStyle(color: textColor, fontSize: 12)),
            const SizedBox(width: AleraTokens.space4),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: AleraTokens.foregroundFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class DropdownEntry<T> extends PopupMenuEntry<T> {
  const DropdownEntry({
    super.key,
    required this.value,
    required this.label,
    this.selected = false,
  });

  final T value;
  final String label;
  final bool selected;

  @override
  double get height => 36;

  @override
  bool represents(T? value) => this.value == value;

  @override
  State<DropdownEntry<T>> createState() => _DropdownEntryState<T>();
}

class _DropdownEntryState<T> extends State<DropdownEntry<T>> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        autofocus: widget.selected,
        onTap: () => Navigator.of(context).pop(widget.value),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (widget.selected)
                const Icon(
                  Icons.check,
                  size: 16,
                  color: AleraTokens.foreground,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
