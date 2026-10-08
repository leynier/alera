import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

const String _unknownRequestPrefix = 'Unknown terminal host request';

/// Whether [error] is the host's answer to a request it does not implement,
/// which is how an older runtime refuses the `mcp.*` verbs.
bool isUnsupportedMcpRequest(Object error) {
  return error is StateError && error.message.startsWith(_unknownRequestPrefix);
}

/// Sentence-case text for an MCP settings or grants failure.
String mcpAccessErrorMessage(Object error) {
  if (isUnsupportedMcpRequest(error)) {
    return 'Update the Alera runtime to use MCP Control.';
  }
  if (error is TerminalHostConflictException) {
    return switch (error.code) {
      'runtime_name_taken' =>
        'Another runtime in your Alera account already uses this name.',
      _ => error.message,
    };
  }
  if (error is TerminalHostConnectionClosedException) {
    return 'The Alera runtime is not reachable.';
  }
  if (error is StateError) {
    return error.message;
  }
  if (error is FormatException) {
    return error.message;
  }
  return error.toString();
}
