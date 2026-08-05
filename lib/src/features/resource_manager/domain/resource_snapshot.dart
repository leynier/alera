/// Wire models for the runtime host's `resources.snapshot` response.
///
/// Read-only data off the socket, so these parse defensively: the app can
/// attach to an older sidecar that answers with fewer fields, and a missing
/// value must degrade to "unknown" rather than throw.
///
/// Every `cpuPercent` here is what `sysinfo` measures, percent of a *single*
/// core, so it exceeds 100% for anything spread over more than one. The wire
/// keeps that unit because an already-running older sidecar sends it and the
/// meaning must not depend on which side is newer; `machineCpuShare` converts it
/// for display.
library;

class ResourceHostMetrics {
  const ResourceHostMetrics({
    required this.totalMemoryBytes,
    required this.availableMemoryBytes,
    required this.usedMemoryBytes,
    required this.memoryUsagePercent,
    required this.cpuCoreCount,
    required this.loadAverage1m,
  });

  factory ResourceHostMetrics.fromJson(Map<String, Object?> json) {
    return ResourceHostMetrics(
      totalMemoryBytes: _intValue(json['totalMemoryBytes']),
      availableMemoryBytes: _intValue(json['availableMemoryBytes']),
      usedMemoryBytes: _intValue(json['usedMemoryBytes']),
      memoryUsagePercent: _doubleValue(json['memoryUsagePercent']),
      cpuCoreCount: _intValue(json['cpuCoreCount']),
      loadAverage1m: _doubleValue(json['loadAverage1m']),
    );
  }

  static const empty = ResourceHostMetrics(
    totalMemoryBytes: 0,
    availableMemoryBytes: 0,
    usedMemoryBytes: 0,
    memoryUsagePercent: 0,
    cpuCoreCount: 0,
    loadAverage1m: 0,
  );

  final int totalMemoryBytes;
  final int availableMemoryBytes;
  final int usedMemoryBytes;
  final double memoryUsagePercent;
  final int cpuCoreCount;

  /// Always zero on Windows, which has no load average.
  final double loadAverage1m;

  bool get hasMemoryReading => totalMemoryBytes > 0;
}

/// One measured process subtree: the app itself or the runtime host.
class ResourceProcessSample {
  const ResourceProcessSample({
    required this.pid,
    required this.cpuPercent,
    required this.memoryBytes,
    required this.processCount,
    required this.history,
  });

  static ResourceProcessSample? tryFromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final json = Map<String, Object?>.from(value);
    return ResourceProcessSample(
      pid: _intValue(json['pid']),
      cpuPercent: _doubleValue(json['cpuPercent']),
      memoryBytes: _intValue(json['memoryBytes']),
      processCount: _intValue(json['processCount']),
      history: _intList(json['history']),
    );
  }

  final int pid;
  final double cpuPercent;
  final int memoryBytes;
  final int processCount;

  /// Memory samples, oldest first. Only memory is historized; a CPU sparkline
  /// at this cadence is noise.
  final List<int> history;
}

/// One terminal session as the host sees it, whether or not the app still has
/// a tab for it.
class ResourceSessionSample {
  const ResourceSessionSample({
    required this.sessionId,
    required this.workspaceId,
    required this.tabId,
    required this.running,
    required this.shellPid,
    required this.measured,
    required this.cpuPercent,
    required this.memoryBytes,
    required this.processCount,
    required this.history,
  });

  static ResourceSessionSample? tryFromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final json = Map<String, Object?>.from(value);
    final sessionId = json['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) {
      return null;
    }
    return ResourceSessionSample(
      sessionId: sessionId,
      workspaceId: _stringValue(json['workspaceId']),
      tabId: _stringValue(json['tabId']),
      running: json['running'] == true,
      shellPid: json['shellPid'] is num
          ? (json['shellPid']! as num).toInt()
          : null,
      measured: json['measured'] == true,
      cpuPercent: _doubleValue(json['cpuPercent']),
      memoryBytes: _intValue(json['memoryBytes']),
      processCount: _intValue(json['processCount']),
      history: _intList(json['history']),
    );
  }

  final String sessionId;
  final String workspaceId;
  final String tabId;
  final bool running;

  /// Absent once the shell exits: the OS recycles pids, so the host drops it
  /// rather than let a stale value point at an unrelated process.
  final int? shellPid;

  /// Whether the host actually found this session's process in the table.
  final bool measured;
  final double cpuPercent;
  final int memoryBytes;
  final int processCount;
  final List<int> history;
}

class ResourceSnapshot {
  const ResourceSnapshot({
    required this.collectedAt,
    required this.warming,
    required this.host,
    required this.hostProcess,
    required this.appProcess,
    required this.sessions,
    required this.totalCpuPercent,
    required this.totalMemoryBytes,
    this.error,
  });

  factory ResourceSnapshot.fromJson(Map<String, Object?> json) {
    final processes = json['processes'];
    final processMap = processes is Map
        ? Map<String, Object?>.from(processes)
        : const <String, Object?>{};
    final host = json['host'];
    final totals = json['totals'];
    final totalsMap = totals is Map
        ? Map<String, Object?>.from(totals)
        : const <String, Object?>{};
    return ResourceSnapshot(
      collectedAt: _timestamp(json['collectedAt']),
      warming: json['warming'] == true,
      host: host is Map
          ? ResourceHostMetrics.fromJson(Map<String, Object?>.from(host))
          : ResourceHostMetrics.empty,
      hostProcess: ResourceProcessSample.tryFromJson(processMap['host']),
      appProcess: ResourceProcessSample.tryFromJson(processMap['app']),
      sessions: <ResourceSessionSample>[
        for (final item in (json['sessions'] as List? ?? const <Object?>[]))
          ?ResourceSessionSample.tryFromJson(item),
      ],
      totalCpuPercent: _doubleValue(totalsMap['cpuPercent']),
      totalMemoryBytes: _intValue(totalsMap['memoryBytes']),
    );
  }

  /// The state before any reading exists: a host that does not support the
  /// verb, a failed request, or the moment right after the panel opens.
  ///
  /// Only the last of those is warming. A host that could not answer is not
  /// measuring anything, and reporting it as such tells the user to wait for a
  /// number that is never coming.
  factory ResourceSnapshot.unavailable({String? error}) {
    return ResourceSnapshot(
      collectedAt: DateTime.now().toUtc(),
      warming: error == null,
      host: ResourceHostMetrics.empty,
      hostProcess: null,
      appProcess: null,
      sessions: const <ResourceSessionSample>[],
      totalCpuPercent: 0,
      totalMemoryBytes: 0,
      error: error,
    );
  }

  final DateTime collectedAt;

  /// The sampler has not produced two refreshes yet, so CPU is not meaningful.
  final bool warming;
  final ResourceHostMetrics host;
  final ResourceProcessSample? hostProcess;
  final ResourceProcessSample? appProcess;
  final List<ResourceSessionSample> sessions;
  final double totalCpuPercent;
  final int totalMemoryBytes;
  final String? error;

  bool get hasReading => !warming && error == null;

  ResourceSnapshot withError(String error) {
    return ResourceSnapshot(
      collectedAt: collectedAt,
      warming: warming,
      host: host,
      hostProcess: hostProcess,
      appProcess: appProcess,
      sessions: sessions,
      totalCpuPercent: totalCpuPercent,
      totalMemoryBytes: totalMemoryBytes,
      error: error,
    );
  }
}

DateTime _timestamp(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return DateTime.now().toUtc();
}

int _intValue(Object? value) => value is num ? value.toInt() : 0;

double _doubleValue(Object? value) => value is num ? value.toDouble() : 0;

String _stringValue(Object? value) => value is String ? value : '';

List<int> _intList(Object? value) {
  if (value is! List) {
    return const <int>[];
  }
  return <int>[
    for (final item in value)
      if (item is num) item.toInt(),
  ];
}
