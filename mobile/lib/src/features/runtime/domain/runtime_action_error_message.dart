import 'dart:async';

import 'package:alera_mobile/src/core/errors/user_facing_error_message.dart';

/// The sentence a failed runtime write (Source Control, Pull Request, AI
/// text) shows. The runtime already words its errors the way desktop words
/// them, so only transport failures need translating; a dropped socket keeps
/// its own text ("Could not reach the host") instead of reading as a git or
/// `gh` failure.
String runtimeActionErrorMessage(Object error) => switch (error) {
  TimeoutException() => 'The runtime did not answer in time.',
  _ => userFacingErrorMessage(error),
};
