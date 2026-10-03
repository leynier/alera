import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

/// Snapshots up to this size decode in place; spawning a worker costs more.
const int terminalSnapshotInlineDecodeLimit = 64 * 1024;

/// A restored scrollback as it arrived: raw bytes, or the base64 the host
/// sent, still undecoded.
///
/// An attach or full resync carries up to the host's restore budget, 2.5 MB
/// by default. Decoding the base64 and then the UTF-8 of that on the UI
/// isolate blocked a phone for several frames each time a tab opened, so a
/// large payload is decoded on a short-lived worker instead.
final class TerminalSnapshotPayload {
  TerminalSnapshotPayload.bytes(List<int> this._bytes) : _base64 = null;

  TerminalSnapshotPayload.base64(String this._base64) : _bytes = null;

  static final TerminalSnapshotPayload empty = TerminalSnapshotPayload.bytes(
    const <int>[],
  );

  final List<int>? _bytes;
  final String? _base64;

  /// Bytes, or base64 characters, held until the restore takes them.
  int get size => _bytes?.length ?? _base64?.length ?? 0;

  bool get isEmpty => size == 0;

  /// The text, decoded here, when the payload is small enough not to matter.
  String? decodeInline() {
    if (size > terminalSnapshotInlineDecodeLimit) {
      return null;
    }
    return _decode(_bytes, _base64);
  }

  /// The text, decoded on a worker isolate. A string comes back without a
  /// copy, so only the decoding moves off the UI isolate.
  Future<String> decodeOffMainIsolate() {
    final bytes = _bytes;
    final base64 = _base64;
    return Isolate.run(() => _decode(bytes, base64));
  }
}

String _decode(List<int>? bytes, String? base64) {
  final raw =
      bytes ??
      (base64 == null || base64.isEmpty ? const <int>[] : base64Decode(base64));
  return const Utf8Decoder(allowMalformed: true).convert(raw);
}

/// Keeps a restored snapshot ahead of the live output that follows it while
/// the snapshot decodes off the UI isolate.
///
/// The host sends live output right behind an attach or resync reply, and the
/// snapshot replaces the emulator. Output that reached the emulator before a
/// late snapshot would be wiped by it, so it is held here and released, in
/// order, once the snapshot is in.
class TerminalSnapshotGate({
  required final void Function(String text, int? cols, int? rows) restore,
  required final void Function(String text) live,
  required final void Function(int size) pending,
}) {
  int _generation = 0;
  List<String>? _held;

  bool get debugHoldingLiveOutput => _held != null;

  /// Restores [payload], inline when small and otherwise once a worker has
  /// decoded it. Supersedes any snapshot still decoding.
  void begin(TerminalSnapshotPayload payload, {int? cols, int? rows}) {
    final generation = ++_generation;
    _held = null;
    if (payload.isEmpty) {
      return;
    }
    final inline = payload.decodeInline();
    if (inline != null) {
      restore(inline, cols, rows);
      return;
    }
    final held = <String>[];
    _held = held;
    pending(payload.size);
    void finish(String text) {
      if (generation != _generation) {
        return;
      }
      _held = null;
      restore(text, cols, rows);
      held.forEach(live);
    }

    unawaited(
      payload.decodeOffMainIsolate().then(
        finish,
        // A payload that will not decode restores nothing, but the live
        // output behind it must still reach the screen.
        onError: (Object _) => finish(''),
      ),
    );
  }

  void addLive(String text) {
    final held = _held;
    if (held != null) {
      held.add(text);
    } else {
      live(text);
    }
  }

  /// Drops a snapshot still decoding, and the output held behind it.
  void cancel() {
    _generation += 1;
    _held = null;
  }
}
