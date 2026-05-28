part of 'codex_runtime_home_service.dart';

String _trustSignature(_CodexHookTrustEntry entry) {
  return jsonEncode(
    _canonicalize(<String, Object?>{
      'eventLabel': entry.eventLabel,
      'command': entry.command,
      'timeoutSec': entry.timeoutSec,
      'async': entry.async,
      'matcher': entry.matcher,
      'statusMessage': entry.statusMessage,
    }),
  );
}

String _computeTrustKey(_CodexHookTrustEntry entry) {
  return '${_canonicalTrustPath(entry.sourcePath)}:${entry.eventLabel}:${entry.groupIndex}:${entry.handlerIndex}';
}

String _canonicalTrustPath(String sourcePath) {
  try {
    return File(sourcePath).resolveSymbolicLinksSync();
  } catch (_) {
    return sourcePath;
  }
}

String _computeTrustedHash(_CodexHookTrustEntry entry) {
  final handler = <String, Object?>{
    'type': 'command',
    'command': entry.command,
    'timeout': entry.timeoutSec == null
        ? 600
        : entry.timeoutSec!.clamp(1, 1 << 31),
    'async': entry.async ?? false,
    if (entry.statusMessage != null) 'statusMessage': entry.statusMessage,
  };
  final identity = <String, Object?>{
    'event_name': entry.eventLabel,
    'hooks': <Object?>[handler],
    if (entry.matcher != null) 'matcher': entry.matcher,
  };
  final serialized = jsonEncode(_canonicalize(identity));
  return 'sha256:${sha256.convert(utf8.encode(serialized))}';
}

Object? _canonicalize(Object? value) {
  if (value is List) {
    return <Object?>[for (final item in value) _canonicalize(item)];
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return <String, Object?>{
      for (final entry in entries)
        entry.key.toString(): _canonicalize(entry.value),
    };
  }
  return value;
}

_ParsedTrustKey? _parseTrustKey(String key) {
  final lastColon = key.lastIndexOf(':');
  if (lastColon < 0) {
    return null;
  }
  final secondLast = key.lastIndexOf(':', lastColon - 1);
  if (secondLast < 0) {
    return null;
  }
  final thirdLast = key.lastIndexOf(':', secondLast - 1);
  if (thirdLast < 0) {
    return null;
  }
  final sourcePath = key.substring(0, thirdLast);
  if (sourcePath.isEmpty) {
    return null;
  }
  return _ParsedTrustKey(sourcePath: sourcePath);
}

@visibleForTesting
String computeCodexTrustedHashForTesting({
  required String sourcePath,
  required String eventLabel,
  required int groupIndex,
  required int handlerIndex,
  required String command,
  int? timeoutSec,
  bool? async,
  String? matcher,
  String? statusMessage,
}) {
  return _computeTrustedHash(
    _CodexHookTrustEntry(
      sourcePath: sourcePath,
      eventLabel: eventLabel,
      groupIndex: groupIndex,
      handlerIndex: handlerIndex,
      command: command,
      timeoutSec: timeoutSec,
      async: async,
      matcher: matcher,
      statusMessage: statusMessage,
    ),
  );
}
