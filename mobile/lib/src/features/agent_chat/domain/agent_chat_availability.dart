/// Whether the phone can act on a chat right now, from the connection to the
/// runtime and from what the runtime says about the chat itself.
enum AgentChatAvailability {
  /// Connected and writable.
  live,

  /// The connection is being rebuilt; the last snapshot stays on screen.
  reconnecting,

  /// The runtime cannot be reached; the last snapshot stays readable.
  offline,

  /// The runtime keeps the chat but does not accept input for it, such as an
  /// archived chat or one whose provider is unavailable on that host.
  readOnly;

  /// Sending, answering requests, and stopping all need a live, writable chat.
  bool get allowsInput => this == live;
}

/// Reads the state the chat body is in. A failed or pending refresh with a
/// snapshot already shown keeps that snapshot: the connection controller
/// rebuilds on every foreground probe, and blanking the timeline there would
/// throw away the reader's scroll position for a transient reconnect.
AgentChatAvailability agentChatAvailability({
  required bool refreshing,
  required bool failed,
  required bool disconnected,
  required bool readOnly,
}) {
  if (failed) return .offline;
  if (refreshing || disconnected) return .reconnecting;
  if (readOnly) return .readOnly;
  return .live;
}
