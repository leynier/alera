import 'dart:async';

import 'package:flutter/material.dart';

/// Lets a field consume non-text clipboard content before Flutter pastes text.
final class AleraClipboardPasteAction(final Future<bool> Function() _onPaste)
    extends Action<PasteTextIntent> {
  @override
  bool get isActionEnabled => callingAction?.isActionEnabled ?? true;

  @override
  Object? invoke(PasteTextIntent intent) {
    final defaultAction = callingAction;
    unawaited(_invokePaste(intent, defaultAction));
    return null;
  }

  Future<void> _invokePaste(
    PasteTextIntent intent,
    Action<PasteTextIntent>? defaultAction,
  ) async {
    if (await _onPaste()) {
      return;
    }
    defaultAction?.invoke(intent);
  }
}
