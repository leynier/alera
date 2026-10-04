/// Numeric limits enforced by the runtime (`validate_definition` in
/// `rust/alera-core/src/runtime/automation_store.rs`). The editor reports a
/// value outside them inline instead of clamping it silently.
enum AutomationNumericField(
  final String key,
  final String label,
  final int min,
  final int max,
  final int defaultValue,
  final String unit,
) {
  queueCap('queueCap', 'Queue Cap', 1, 10, 10, 'runs'),
  inactivityTimeoutSeconds(
    'inactivityTimeoutSeconds',
    'Inactivity Timeout',
    1,
    86400,
    7200,
    'seconds',
  ),
  heartbeatIntervalSeconds(
    'heartbeatIntervalSeconds',
    'Heartbeat Interval',
    1,
    86400,
    60,
    'seconds',
  ),
  misfireGraceSeconds(
    'misfireGraceSeconds',
    'Misfire Grace',
    0,
    86400,
    900,
    'seconds',
  ),
  retryMaxAttempts('retryMaxAttempts', 'Retry Attempts', 1, 3, 3, 'launches'),
  retryBackoffSeconds(
    'retryBackoffSeconds',
    'Retry Backoff',
    1,
    86400,
    60,
    'seconds',
  ),
  circuitFailureThreshold(
    'circuitFailureThreshold',
    'Circuit Failure Threshold',
    1,
    10,
    3,
    'failures',
  ),
  circuitOpenSeconds(
    'circuitOpenSeconds',
    'Circuit Open',
    1,
    604800,
    900,
    'seconds',
  ),
  precheckTimeoutSeconds(
    'precheckTimeoutSeconds',
    'Precheck Timeout',
    1,
    900,
    120,
    'seconds',
  ),
  maxScheduledRuns(
    'maxScheduledRuns',
    'Max Scheduled Runs',
    1,
    1 << 31,
    0,
    'runs',
  );

  /// The heartbeat interval is also bounded by the inactivity timeout.
  String? validate(String text, {int? inactivityTimeoutSeconds}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return this == maxScheduledRuns ? null : 'Enter a number.';
    }
    final value = int.tryParse(trimmed);
    if (value == null) return 'Enter a whole number.';
    final upper = this == heartbeatIntervalSeconds
        ? (inactivityTimeoutSeconds ?? max)
        : max;
    if (value < min || value > upper) {
      return this == maxScheduledRuns
          ? 'Use at least $min.'
          : this == heartbeatIntervalSeconds && upper != max
          ? 'Use $min to $upper seconds, no longer than the inactivity timeout.'
          : 'Use $min to $upper $unit.';
    }
    return null;
  }
}

const List<String> automationOverlapPolicies = <String>[
  'skip',
  'runLatestOnce',
  'queue',
  'forceParallel',
];

const List<String> automationMisfirePolicies = <String>[
  'skip',
  'runLatestOnce',
  'queue',
];

const List<String> automationSetupPolicies = <String>[
  'wait',
  'parallel',
  'skip',
];

const List<String> automationCleanupPolicies = <String>[
  'preserve',
  'onSuccess',
];

String automationPolicyLabel(String value) => switch (value) {
  'skip' => 'Skip',
  'runLatestOnce' => 'Run Latest Once',
  'queue' => 'Queue',
  'forceParallel' => 'Run In Parallel',
  'wait' => 'Wait For Setup',
  'parallel' => 'Run With Setup',
  'preserve' => 'Keep Workspace',
  'onSuccess' => 'Clean Up On Success',
  _ => value,
};
