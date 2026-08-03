import 'dart:collection';

import 'package:alera/src/features/workbench/domain/terminal_composer_attachment.dart';
import 'package:alera/src/features/workbench/domain/terminal_image_paste.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class TerminalComposerController extends ChangeNotifier {
  final textController = TextEditingController();
  final focusNode = FocusNode(debugLabel: 'TerminalComposer');
  final dropTargetKey = GlobalKey(debugLabel: 'TerminalComposerDropTarget');

  final List<TerminalComposerAttachment> _attachments =
      <TerminalComposerAttachment>[];
  late final List<TerminalComposerAttachment> attachments =
      UnmodifiableListView<TerminalComposerAttachment>(_attachments);
  bool _visible = false;
  bool _submitting = false;
  bool _disposed = false;
  int _nextAttachmentId = 0;

  bool get visible => _visible;
  bool get submitting => _submitting;

  void addAttachment({
    required TerminalComposerAttachmentKind kind,
    required String path,
    required String displayName,
  }) {
    if (_disposed) {
      return;
    }
    _attachments.add(
      TerminalComposerAttachment(
        id: 'attachment-${_nextAttachmentId++}',
        kind: kind,
        path: path,
        displayName: displayName,
      ),
    );
    notifyListeners();
  }

  void addPathAttachment(String path, {TerminalComposerAttachmentKind? kind}) {
    if (_disposed) {
      return;
    }
    final attachment = _pathAttachment(path, kind: kind);
    if (attachment != null) {
      _attachments.add(attachment);
      notifyListeners();
    }
  }

  void addPathAttachments(Iterable<String> paths) {
    if (_disposed) {
      return;
    }
    var changed = false;
    for (final path in paths) {
      final attachment = _pathAttachment(path);
      if (attachment != null) {
        _attachments.add(attachment);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  TerminalComposerAttachment? _pathAttachment(
    String path, {
    TerminalComposerAttachmentKind? kind,
  }) {
    if (path.isEmpty) {
      return null;
    }
    final resolvedKind = kind ?? terminalComposerAttachmentKindForPath(path);
    final displayName = sanitizeTerminalImagePastePath(p.basename(path));
    return TerminalComposerAttachment(
      id: 'attachment-${_nextAttachmentId++}',
      kind: resolvedKind,
      path: path,
      displayName: displayName.isEmpty
          ? resolvedKind == TerminalComposerAttachmentKind.image
                ? 'Pasted Image'
                : 'Pasted File'
          : displayName,
    );
  }

  void removeAttachment(String id) {
    removeAttachments(<String>[id]);
  }

  void removeAttachments(Iterable<String> ids) {
    if (_disposed) {
      return;
    }
    final removedIds = ids.toSet();
    if (removedIds.isEmpty) {
      return;
    }
    final previousLength = _attachments.length;
    _attachments.removeWhere(
      (attachment) => removedIds.contains(attachment.id),
    );
    if (_attachments.length != previousLength) {
      notifyListeners();
    }
  }

  void toggle() => _setVisible(!_visible);

  void show() => _setVisible(true);

  void hide() => _setVisible(false);

  void setSubmitting(bool value) {
    if (_disposed || _submitting == value) {
      return;
    }
    _submitting = value;
    notifyListeners();
  }

  void _setVisible(bool value) {
    if (_disposed || _visible == value) {
      return;
    }
    _visible = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _attachments.clear();
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
