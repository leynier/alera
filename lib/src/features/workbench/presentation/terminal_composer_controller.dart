import 'package:flutter/material.dart';

class TerminalComposerController extends ChangeNotifier {
  final textController = TextEditingController();
  final focusNode = FocusNode(debugLabel: 'TerminalComposer');

  bool _visible = false;
  bool _submitting = false;
  bool _disposed = false;

  bool get visible => _visible;
  bool get submitting => _submitting;

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
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
