import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

enum AleraToastTone { success, warning, error, info }

/// A toast with an [actionLabel] and [onAction] shows a button; the host
/// accepts pointer input on that card only, and pressing the button also
/// dismisses the toast.
class const AleraToastData({
  required final String message,
  required final AleraToastTone tone,
  required final Duration duration,
  final String? actionLabel,
  final VoidCallback? onAction,
}) {
  bool get hasAction =>
      onAction != null && (actionLabel?.trim().isNotEmpty ?? false);
}

abstract final class AleraToast {
  static final StreamController<AleraToastData> _controller =
      StreamController<AleraToastData>.broadcast();

  static Stream<AleraToastData> get stream => _controller.stream;

  /// For warnings and errors whose message is a sentence worth reading.
  static const Duration longDuration = AleraTokens.toastLongDuration;

  static void show(
    BuildContext context, {
    required String message,
    AleraToastTone tone = AleraToastTone.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!context.mounted) {
      return;
    }

    publish(
      message: message,
      tone: tone,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void publish({
    required String message,
    AleraToastTone tone = AleraToastTone.info,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      return;
    }

    _controller.add(
      AleraToastData(
        message: trimmedMessage,
        tone: tone,
        duration: duration ?? defaultDurationFor(tone),
        actionLabel: actionLabel?.trim(),
        onAction: onAction,
      ),
    );
  }

  /// Errors and warnings stay up long enough to be read; a four second error
  /// is one the user often never sees.
  static Duration defaultDurationFor(AleraToastTone tone) {
    return switch (tone) {
      AleraToastTone.error || AleraToastTone.warning => longDuration,
      AleraToastTone.success ||
      AleraToastTone.info => AleraTokens.toastDuration,
    };
  }
}
