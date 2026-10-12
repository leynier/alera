import 'package:alera_automations/src/automation_readiness.dart';

const List<String> _noisyPrefixes = <String>[
  'Exception: ',
  'Bad state: ',
  'StateError: ',
  'FormatException: ',
  'Invalid argument(s): ',
];

/// A message fit for a toast or an inline notice: readiness issues are
/// unwrapped, and the Dart type prefix a thrown error carries is removed.
String automationErrorMessage(Object? error) {
  if (error is AutomationReadinessException) return error.toString();
  var text = (error?.toString() ?? '').trim();
  var stripped = true;
  while (stripped) {
    stripped = false;
    for (final prefix in _noisyPrefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
        stripped = true;
      }
    }
  }
  return text.isEmpty ? 'Something went wrong. Try again.' : text;
}
