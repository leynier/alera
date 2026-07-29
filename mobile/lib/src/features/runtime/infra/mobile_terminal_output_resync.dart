part of 'mobile_runtime_client.dart';

/// Recovers from the host pausing this client's output lane.
///
/// The host's per-client terminal queue is bounded, and one frame it cannot
/// accept parks the client in the session's paused set. Nothing clears that on
/// its own: the only ways out are this resume request and a fresh attach, which
/// is why the terminal used to stay frozen on old content until the user left
/// the screen and came back. The host asks with `outputResyncRequired` and
/// re-arms that ask every few milliseconds until the client answers, so the
/// answer has to be idempotent per session.
mixin MobileRuntimeTerminalOutputResync {
  final Map<String, Future<void>> _pendingOutputResyncs =
      <String, Future<void>>{};

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload,
    Duration? timeout,
  ]);

  void emitTerminalOutput(MobileTerminalOutputEvent event);

  bool get isConnectionUsable;

  void handleOutputResyncRequired(Map<String, Object?> payload) {
    final sessionId = payload['sessionId'];
    if (sessionId is! String || sessionId.isEmpty || !isConnectionUsable) {
      return;
    }
    // The host retries until it sees the resume, so without this the retries
    // would each open their own request.
    if (_pendingOutputResyncs.containsKey(sessionId)) {
      return;
    }
    late final Future<void> resync;
    resync = _resumeOutput(sessionId).whenComplete(() {
      if (identical(_pendingOutputResyncs[sessionId], resync)) {
        _pendingOutputResyncs.remove(sessionId);
      }
    });
    _pendingOutputResyncs[sessionId] = resync;
  }

  Future<void> _resumeOutput(String sessionId) async {
    try {
      final payload = await requestMap('setOutputPaused', <String, Object?>{
        'sessionId': sessionId,
        'paused': false,
      });
      // A delta resume needs nothing here: the host already pushed the missed
      // bytes down the terminal lane, ahead of whatever comes next.
      if (payload['delta'] == true) {
        return;
      }
      // Absent means replace, matching the desktop client. The host could not
      // place this client in the stream any more, so it answered with a
      // snapshot instead of a gap it could not prove.
      final encoded = payload['snapshotBase64'];
      if (encoded is! String || encoded.isEmpty) {
        return;
      }
      emitTerminalOutput(
        MobileTerminalOutputEvent(
          sessionId,
          base64Decode(encoded),
          replacesScrollback: true,
        ),
      );
    } on Object catch (error, stackTrace) {
      // The host re-arms its own retry, so a failed attempt is picked up by the
      // next event rather than looped here. It is still recorded: a resync that
      // keeps failing shows up as missing terminal output, which is otherwise
      // very hard to explain after the fact.
      Logger('MobileTerminalResync').warning(
        'failed to resynchronise output for session $sessionId',
        error,
        stackTrace,
      );
    }
  }
}
