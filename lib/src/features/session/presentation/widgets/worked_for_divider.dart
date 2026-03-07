import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/shared/utils/cast_utils.dart';
import 'package:flutter/material.dart';

class WorkedForDivider extends StatelessWidget {
  const WorkedForDivider({
    super.key,
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String? label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey<String>('worked-divider'),
      children: <Widget>[
        const Expanded(
          child: Divider(
            color: AleraTokens.borderSubtle,
            height: 1,
            thickness: 1,
          ),
        ),
        InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label ?? '',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Icon(
                  expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  size: 14,
                  color: AleraTokens.foregroundFaint,
                ),
              ],
            ),
          ),
        ),
        const Expanded(
          child: Divider(
            color: AleraTokens.borderSubtle,
            height: 1,
            thickness: 1,
          ),
        ),
      ],
    );
  }
}

String? workedForLabel(TimelineCell separatorCell) {
  final metadata = separatorCell.metadata;
  final hasMetrics = _hasRuntimeMetrics(metadata);
  final formatted = _formatWorkedDuration(metadata);
  if (formatted != null) {
    return 'Worked for $formatted';
  }
  if (hasMetrics) {
    return 'Work finished';
  }
  return null;
}

String? _formatWorkedDuration(Map<String, dynamic> metadata) {
  final durationMs = _durationMs(metadata);
  if (durationMs == null || durationMs <= 0) {
    return null;
  }
  final totalSeconds = (durationMs / 1000).round();
  if (totalSeconds <= 0) {
    return '0s';
  }
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (days > 0) {
    if (hours > 0) {
      return '${days}d ${hours}h';
    }
    if (minutes > 0) {
      return '${days}d ${minutes}m';
    }
    return '${days}d';
  }
  if (hours > 0) {
    if (minutes > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${hours}h';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  return '${totalSeconds}s';
}

num? _durationMs(Map<String, dynamic> metadata) {
  return asNum(metadata['computedDurationMs']) ??
      asNum(metadata['computed_duration_ms']) ??
      asNum(metadata['elapsedMs']) ??
      asNum(metadata['elapsed_ms']) ??
      asNum(metadata['durationMs']) ??
      asNum(metadata['duration_ms']) ??
      _durationFromTimestamps(metadata);
}

bool _hasRuntimeMetrics(Map<String, dynamic> metadata) {
  final runtime = metadata['runtimeMetrics'];
  if (runtime is Map && runtime.isNotEmpty) {
    return true;
  }
  final totalTokens =
      asNum(metadata['totalTokens']) ??
      asNum(metadata['total_tokens']) ??
      asNum(asMap(metadata['usage'])['totalTokens']) ??
      asNum(asMap(metadata['usage'])['total_tokens']);
  return totalTokens != null && totalTokens > 0;
}

num? _durationFromTimestamps(Map<String, dynamic> metadata) {
  final startRaw =
      asNum(metadata['startedAt']) ??
      asNum(metadata['started_at']) ??
      asNum(metadata['createdAt']) ??
      asNum(metadata['created_at']);
  final endRaw =
      asNum(metadata['completedAt']) ??
      asNum(metadata['completed_at']) ??
      asNum(metadata['updatedAt']) ??
      asNum(metadata['updated_at']);
  if (startRaw == null || endRaw == null) {
    return null;
  }
  final startMs = _normalizeEpochToMs(startRaw);
  final endMs = _normalizeEpochToMs(endRaw);
  if (endMs < startMs) {
    return null;
  }
  return endMs - startMs;
}

num _normalizeEpochToMs(num raw) {
  // < 10^11 is likely epoch seconds, otherwise milliseconds.
  return raw < 100000000000 ? raw * 1000 : raw;
}
