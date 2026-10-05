import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

enum AleraToastTone { success, warning, error, info }

class const AleraToastData({
  required final String message,
  required final AleraToastTone tone,
  required final Duration duration,
});

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
  }) {
    if (!context.mounted) {
      return;
    }

    publish(message: message, tone: tone, duration: duration);
  }

  static void publish({
    required String message,
    AleraToastTone tone = AleraToastTone.info,
    Duration? duration,
  }) {
    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      return;
    }

    _controller.add(
      AleraToastData(
        message: trimmedMessage,
        tone: tone,
        duration: duration ?? AleraTokens.toastDuration,
      ),
    );
  }
}
