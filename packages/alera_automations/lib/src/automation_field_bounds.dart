/// Numeric limits enforced by the runtime (`validate_definition` in
/// `rust/alera-core/src/runtime/automation_store.rs`). The editor reports a
/// value outside them inline instead of clamping it silently.
enum AutomationNumericField(
  final String key,
  final String label,
  final int min,
  final int max,
  final int defaultValue,
  final String unit, {
  final bool editable = false,
}) {
  queueCap('queueCap', 'Queue Cap', 1, 10, 10, 'runs'),
  inactivityTimeoutSeconds(
    'inactivityTimeoutSeconds',
    'Inactivity Timeout',
    1,
    86400,
    7200,
    'seconds',
    editable: true,
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
  retryMaxAttempts(
    'retryMaxAttempts',
    'Retry Attempts',
    1,
    3,
    3,
    'launches',
    editable: true,
  ),
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
    editable: true,
  ),
  maxScheduledRuns(
    'maxScheduledRuns',
    'Max Scheduled Runs',
    1,
    1 << 31,
    0,
    'runs',
    editable: true,
  );

  /// The fields an editor offers. The others keep their stored values and
  /// still round-trip through `toDefinition` unchanged.
  static List<AutomationNumericField> get editableFields =>
      values.where((field) => field.editable).toList(growable: false);

  /// The heartbeat interval and the inactivity timeout also bound each other:
  /// the runtime rejects a heartbeat longer than the timeout.
  String? validate(
    String text, {
    int? inactivityTimeoutSeconds,
    int? heartbeatIntervalSeconds,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return this == maxScheduledRuns ? null : 'Enter a number.';
    }
    final value = int.tryParse(trimmed);
    if (value == null) return 'Enter a whole number.';
    final upper = this == AutomationNumericField.heartbeatIntervalSeconds
        ? (inactivityTimeoutSeconds ?? max)
        : max;
    final lower =
        this == AutomationNumericField.inactivityTimeoutSeconds &&
            heartbeatIntervalSeconds != null &&
            heartbeatIntervalSeconds > min
        ? heartbeatIntervalSeconds
        : min;
    if (value < lower || value > upper) {
      return this == maxScheduledRuns
          ? 'Use at least $min.'
          : this == AutomationNumericField.heartbeatIntervalSeconds &&
                upper != max
          ? 'Use $min to $upper seconds, no longer than the inactivity timeout.'
          : lower != min
          ? 'Use $lower to $upper seconds, no shorter than the heartbeat interval.'
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
