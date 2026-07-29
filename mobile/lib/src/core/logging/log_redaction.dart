/// Masks secrets before a log line reaches disk or a crash report.
///
/// Redaction lives in the sink rather than at the call sites because a
/// diagnostics bundle is meant to be shared, and a call site that forgets to
/// mask looks exactly like one that had nothing to mask.
library;

const String kRedactedPlaceholder = '[redacted]';

/// Values shorter than this are not distinctive enough to register: they would
/// collide with ordinary words and mask unrelated text.
const int kMinRegisteredSecretLength = 8;

final RegExp _keyedSecretPattern = RegExp(
  r'\b(token|secret|password|passwd|api[_-]?key|authorization|deviceToken)\b"?\s*[:=]\s*"?([^\s",;}\)]+)',
  caseSensitive: false,
);

final RegExp _bearerPattern = RegExp(
  r'\bbearer\s+([A-Za-z0-9._\-+/=]+)',
  caseSensitive: false,
);

final Set<String> _registeredSecrets = <String>{};

/// Registers a literal value that must never appear in output.
///
/// The app knows its own runtime host token, so masking the exact value catches
/// it even when it is logged without a recognizable key beside it.
void registerLogSecret(String value) {
  final trimmed = value.trim();
  if (trimmed.length < kMinRegisteredSecretLength) {
    return;
  }
  _registeredSecrets.add(trimmed);
}

/// Drops every registered literal. Exposed for tests, which must not leak
/// registrations into each other.
void resetRegisteredLogSecrets() => _registeredSecrets.clear();

/// Replaces every known secret in [input] with [kRedactedPlaceholder].
String redactLogText(String input) {
  var output = input;
  for (final secret in _registeredSecrets) {
    if (output.contains(secret)) {
      output = output.replaceAll(secret, kRedactedPlaceholder);
    }
  }
  output = output.replaceAllMapped(
    _keyedSecretPattern,
    (match) => '${match.group(1)}=$kRedactedPlaceholder',
  );
  return output.replaceAllMapped(
    _bearerPattern,
    (_) => 'Bearer $kRedactedPlaceholder',
  );
}
