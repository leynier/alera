import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/composer_attachment.dart';
import 'package:alera/src/features/session/domain/pending_message.dart';
import 'package:alera/src/features/session/presentation/widgets/attachment_bar.dart';
import 'package:alera/src/features/session/presentation/widgets/composer_text_controller.dart';
import 'package:alera/src/features/session/presentation/widgets/mention_file_list.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class QueueMessageEditDialog extends StatefulWidget {
  const QueueMessageEditDialog({
    super.key,
    required this.message,
    required this.workspacePath,
    required this.onSave,
    required this.onDelete,
  });

  final PendingMessage message;
  final String? workspacePath;
  final ValueChanged<({String text, List<ComposerAttachment> attachments})> onSave;
  final VoidCallback onDelete;

  @override
  State<QueueMessageEditDialog> createState() => _QueueMessageEditDialogState();
}

class _QueueMessageEditDialogState extends State<QueueMessageEditDialog> {
  late final ComposerTextController _textController;
  late List<ComposerAttachment> _attachments;
  final FocusNode _focusNode = FocusNode();
  List<String> _mentionFiles = const <String>[];
  int _mentionSelectedIndex = 0;
  Timer? _mentionDebounce;

  @override
  void initState() {
    super.initState();
    _textController = ComposerTextController(
      workspacePath: widget.workspacePath,
    )..text = widget.message.text;
    _attachments = List<ComposerAttachment>.of(widget.message.attachments);
    _focusNode.onKeyEvent = _handleKeyEvent;
    _textController.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _mentionDebounce?.cancel();
    _focusNode.dispose();
    _textController.removeListener(_onControllerChanged);
    _textController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    // Intercept Cmd+V / Ctrl+V for clipboard image pasting.
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (Platform.isMacOS
            ? HardwareKeyboard.instance.isMetaPressed
            : HardwareKeyboard.instance.isControlPressed)) {
      _tryPasteImage();
      return KeyEventResult.ignored;
    }

    if (_mentionFiles.isEmpty || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
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
      setState(() {
        _mentionFiles = const <String>[];
        _mentionSelectedIndex = 0;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onControllerChanged() {
    _mentionDebounce?.cancel();
    _mentionDebounce = Timer(
      const Duration(milliseconds: 120),
      _updateMentionState,
    );
  }

  void _updateMentionState() {
    final text = _textController.text;
    final cursor = _textController.selection.baseOffset;
    if (cursor < 0) {
      _clearMention();
      return;
    }
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
    final text = _textController.text;
    final cursor = _textController.selection.baseOffset;
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
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: match.start + relativePath.length + 2,
      ),
    );
    setState(() {
      _mentionFiles = const <String>[];
      _mentionSelectedIndex = 0;
    });
  }

  Future<void> _tryPasteImage() async {
    try {
      final bytes = await Pasteboard.image;
      if (bytes == null || bytes.isEmpty) return;
      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}/alera_paste_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await tempFile.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() {
        _attachments = <ComposerAttachment>[
          ..._attachments,
          ComposerAttachment(
            id: const Uuid().v4(),
            path: tempFile.path,
            displayName: tempFile.path.split('/').last,
            kind: AttachmentKind.image,
          ),
        ];
      });
    } catch (_) {
      // No image in clipboard or write failed - silently ignore.
    }
  }

  void _removeAttachment(String id) {
    setState(() {
      _attachments = _attachments.where((a) => a.id != id).toList(growable: false);
    });
  }

  Future<void> _addAttachment() async {
    final XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[const XTypeGroup(label: 'All files')],
      );
    } catch (_) {
      return;
    }
    if (file == null) {
      return;
    }
    final filePath = file.path;
    final fileName = file.name;
    final kind = _attachmentKindFromPath(filePath);
    final mimeType = kind == AttachmentKind.image ? _imageMimeType(filePath) : null;
    setState(() {
      _attachments = <ComposerAttachment>[
        ..._attachments,
        ComposerAttachment(
          id: const Uuid().v4(),
          kind: kind,
          path: filePath,
          displayName: fileName,
          mimeType: mimeType,
        ),
      ];
    });
  }

  AttachmentKind _attachmentKindFromPath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    if (const <String>{'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(ext)) {
      return AttachmentKind.image;
    }
    return AttachmentKind.file;
  }

  String? _imageMimeType(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return null;
    }
  }

  void _save() {
    widget.onSave((
      text: _textController.text,
      attachments: _attachments,
    ));
    Navigator.of(context).pop();
  }

  void _delete() {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AleraTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
          side: const BorderSide(color: AleraTokens.border),
        ),
        title: const Text(
          'Delete message?',
          style: TextStyle(color: AleraTokens.foreground),
        ),
        content: const Text(
          'This will remove the message from the queue.',
          style: TextStyle(color: AleraTokens.foregroundMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: AleraTokens.foregroundMuted,
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AleraTokens.error,
              foregroundColor: AleraTokens.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        widget.onDelete();
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    });
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 600,
        decoration: BoxDecoration(
          color: AleraTokens.surface,
          borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
          border: Border.all(color: AleraTokens.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Header.
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space16),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  const Text(
                    'Edit queued message',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AleraTokens.foreground,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _cancel,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                    mouseCursor: SystemMouseCursors.click,
                    child: const Padding(
                      padding: EdgeInsets.all(AleraTokens.space4),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: AleraTokens.foregroundFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AleraTokens.border),
            // Content.
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AleraTokens.space16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      // Attachment bar.
                      if (_attachments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AleraTokens.space12,
                          ),
                          child: AttachmentBar(
                            attachments: _attachments,
                            onRemove: _removeAttachment,
                          ),
                        ),
                      // Text field with mention overlay.
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: AleraTokens.surfaceVariant,
                              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                              border: Border.all(color: AleraTokens.border),
                            ),
                            child: TextField(
                              controller: _textController,
                              focusNode: _focusNode,
                              minLines: 3,
                              maxLines: 8,
                              textInputAction: TextInputAction.newline,
                              style: Theme.of(context).textTheme.bodyMedium,
                              decoration: InputDecoration(
                                hintText: 'Edit your message...',
                                filled: true,
                                fillColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                contentPadding: const EdgeInsets.fromLTRB(
                                  AleraTokens.space12,
                                  AleraTokens.space12,
                                  AleraTokens.space12,
                                  AleraTokens.space48,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          // Add attachment button inside text field area.
                          Positioned(
                            left: AleraTokens.space8,
                            bottom: AleraTokens.space8,
                            child: IconButton(
                              onPressed: _addAttachment,
                              tooltip: 'Add photos & files',
                              mouseCursor: SystemMouseCursors.click,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                              padding: const EdgeInsets.all(AleraTokens.space4),
                              icon: const Icon(
                                Icons.add,
                                size: 18,
                                color: AleraTokens.foregroundMuted,
                              ),
                            ),
                          ),
                          // @ mention overlay positioned above text field.
                          if (_mentionFiles.isNotEmpty)
                            Positioned(
                              bottom: 60,
                              left: 0,
                              right: 0,
                              child: Material(
                                elevation: 4,
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: AleraTokens.surfaceElevated,
                                    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                                    border: Border.all(color: AleraTokens.border),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: AleraTokens.shadowSoft,
                                        blurRadius: 8,
                                        offset: Offset(0, -2),
                                      ),
                                    ],
                                  ),
                                  child: MentionFileList(
                                    files: _mentionFiles,
                                    selectedIndex: _mentionSelectedIndex,
                                    onSelect: _selectMention,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: AleraTokens.border),
            // Action bar.
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space12),
              child: Row(
                children: <Widget>[
                  // Delete button (left side).
                  FilledButton(
                    onPressed: _delete,
                    style: FilledButton.styleFrom(
                      backgroundColor: AleraTokens.error,
                      foregroundColor: AleraTokens.onError,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AleraTokens.space16,
                        vertical: AleraTokens.space8,
                      ),
                      minimumSize: const Size(0, 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                      ),
                    ),
                    child: const Text('Delete'),
                  ),
                  const Spacer(),
                  // Save button (right side).
                  FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AleraTokens.accent,
                      foregroundColor: AleraTokens.onAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AleraTokens.space16,
                        vertical: AleraTokens.space8,
                      ),
                      minimumSize: const Size(0, 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
