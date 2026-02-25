import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:flutter/material.dart';

Color statusColor(TimelineCellStatus status) {
  return switch (status) {
    TimelineCellStatus.inProgress => AleraTokens.accent,
    TimelineCellStatus.completed => AleraTokens.success,
    TimelineCellStatus.failed => AleraTokens.error,
    TimelineCellStatus.declined => AleraTokens.warning,
    TimelineCellStatus.info => AleraTokens.foregroundFaint,
  };
}
