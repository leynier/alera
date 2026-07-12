import 'dart:async';

import 'package:flutter/material.dart';

enum AleraToastTone { success, error, info }

class AleraToastData {
  const AleraToastData({
    required this.message,
    required this.tone,
    required this.duration,
  });

  final String message;
  final AleraToastTone tone;
  final Duration duration;
}

abstract final class AleraToast {
  static final StreamController<AleraToastData> _controller =
      StreamController<AleraToastData>.broadcast();

  static Stream<AleraToastData> get stream => _controller.stream;

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
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }
}
