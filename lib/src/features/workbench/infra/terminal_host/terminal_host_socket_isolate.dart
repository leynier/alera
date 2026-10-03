/// Socket reader that runs off the UI isolate.
///
/// It owns the TCP socket, does the framing, and decodes PTY output to text so
/// the main isolate receives something it can hand straight to the emulator.
/// The per-session decoder has to live here: a multi-byte sequence can be split
/// across chunks, and this is the only place that sees every chunk in order.
///
/// No Flutter imports: this runs in a plain isolate.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_frame_codec.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

/// Messages the isolate sends to the main isolate.
const String terminalHostIsolateReady = 'ready';
const String terminalHostIsolateLine = 'line';
const String terminalHostIsolateOutput = 'output';
const String terminalHostIsolateClosed = 'closed';
const String terminalHostIsolateError = 'error';

/// Commands the main isolate sends back.
const String terminalHostIsolateWrite = 'write';
const String terminalHostIsolateClose = 'close';

class const TerminalHostSocketIsolateConfig({
  required final String host,
  required final int port,
  required final SendPort toMain,
  required final int connectTimeoutMillis,
});

/// Isolate entry point. Sends [terminalHostIsolateReady] with its command port
/// once connected, then streams frames until the socket or the owner closes it.
Future<void> terminalHostSocketIsolateMain(
  TerminalHostSocketIsolateConfig config,
) async {
  final toMain = config.toMain;
  final Socket socket;
  try {
    socket = await Socket.connect(
      config.host,
      config.port,
      timeout: Duration(milliseconds: config.connectTimeoutMillis),
    );
  } catch (error) {
    toMain.send(<Object?>[terminalHostIsolateError, error.toString()]);
    toMain.send(const <Object?>[terminalHostIsolateClosed]);
    return;
  }
  socket.setOption(.tcpNoDelay, true);

  final commands = ReceivePort();
  final reader = TerminalHostFrameReader();
  final decoders = <String, ByteConversionSink>{};
  final decoded = <String, StringBuffer>{};
  var closed = false;

  void closeSocket() {
    if (closed) {
      return;
    }
    closed = true;
    socket.destroy();
    commands.close();
  }

  /// One decoder per session, kept across chunks so a split code point is not
  /// corrupted at a frame boundary.
  void emitOutput(String sessionId, Uint8List bytes) {
    final buffer = decoded.putIfAbsent(sessionId, StringBuffer.new);
    final sink = decoders.putIfAbsent(sessionId, () {
      // fromStringSink, not withCallback: the latter only delivers on close,
      // which for a long-lived PTY means never.
      return const Utf8Decoder(allowMalformed: true)
          .startChunkedConversion(StringConversionSink.fromStringSink(buffer));
    });
    sink.add(bytes);
    if (buffer.isEmpty) {
      return;
    }
    final text = buffer.toString();
    buffer.clear();
    toMain.send(<Object?>[terminalHostIsolateOutput, sessionId, text]);
  }

  commands.listen((Object? message) {
    if (message is! List || message.isEmpty) {
      return;
    }
    switch (message[0]) {
      case terminalHostIsolateWrite:
        if (!closed) {
          socket.add(message[1] as List<int>);
        }
      case terminalHostIsolateClose:
        closeSocket();
    }
  });

  socket.listen(
    (Uint8List chunk) {
      for (final frame in reader.add(chunk)) {
        switch (frame) {
          case TerminalHostJsonFrame(:final json):
            toMain.send(<Object?>[
              terminalHostIsolateLine,
              decodeHostLine(json),
            ]);
          case TerminalHostOutputFrame(:final sessionId, :final data):
            emitOutput(sessionId, data);
        }
      }
    },
    onError: (Object error) {
      toMain.send(<Object?>[terminalHostIsolateError, error.toString()]);
      closeSocket();
      toMain.send(const <Object?>[terminalHostIsolateClosed]);
    },
    onDone: () {
      closeSocket();
      toMain.send(const <Object?>[terminalHostIsolateClosed]);
    },
    cancelOnError: true,
  );

  toMain.send(<Object?>[terminalHostIsolateReady, commands.sendPort]);
}

/// Parses a control line here rather than on the UI isolate.
///
/// An attach reply carries the session's scrollback base64'd inside it, and
/// parsing megabytes of JSON was the single largest main-isolate cost of
/// opening a terminal. A line that will not parse is passed through as-is so
/// the owner still reports it the way it always did.
Object? decodeHostLine(String line) {
  final Object? decoded;
  try {
    decoded = jsonDecode(line);
  } catch (_) {
    return line;
  }
  _detachSnapshots(decoded);
  return decoded;
}

/// Decodes a reply's base64 scrollback here and hands it over as transferable
/// bytes.
///
/// Left as a string, a 10 MB snapshot crossed the isolate boundary as a 14 MB
/// copy and was then base64-decoded on the UI isolate, together tens of
/// milliseconds of dropped frames when a tab attached or resynced. Snapshots
/// sit at the top of a message or one map below it (`result`, `payload`).
void _detachSnapshots(Object? message) {
  if (message is! Map<String, Object?>) {
    return;
  }
  _detachSnapshot(message);
  for (final value in message.values) {
    if (value is Map<String, Object?>) {
      _detachSnapshot(value);
    }
  }
}

void _detachSnapshot(Map<String, Object?> map) {
  final encoded = map[terminalHostSnapshotKey];
  if (encoded is! String || encoded.isEmpty) {
    return;
  }
  final Uint8List bytes;
  try {
    bytes = base64Decode(encoded);
  } on FormatException {
    // Leave it for the owner, which reports malformed replies itself.
    return;
  }
  map[terminalHostSnapshotKey] = TransferableTypedData.fromList(<Uint8List>[
    bytes,
  ]);
}

/// Main-isolate side of [decodeHostLine]: takes ownership of transferred
/// snapshots, without copying, before anything reads the message.
Object? adoptTransferredSnapshots(Object? message) {
  if (message is! Map<String, Object?>) {
    return message;
  }
  _adoptSnapshot(message);
  for (final value in message.values) {
    if (value is Map<String, Object?>) {
      _adoptSnapshot(value);
    }
  }
  return message;
}

void _adoptSnapshot(Map<String, Object?> map) {
  final transferred = map[terminalHostSnapshotKey];
  if (transferred is TransferableTypedData) {
    map[terminalHostSnapshotKey] = transferred.materialize().asUint8List();
  }
}

/// Spawns the reader and returns its command port, or null if spawning failed.
///
/// A failure is not fatal: the caller falls back to reading the socket on the
/// main isolate, because losing terminals over an isolate problem would be a
/// far worse outcome than losing the offload.
Future<SendPort?> spawnTerminalHostSocketIsolate({
  required String host,
  required int port,
  required SendPort toMain,
  required Duration connectTimeout,
  required Future<SendPort> Function() awaitReady,
}) async {
  try {
    await Isolate.spawn<TerminalHostSocketIsolateConfig>(
      terminalHostSocketIsolateMain,
      TerminalHostSocketIsolateConfig(
        host: host,
        port: port,
        toMain: toMain,
        connectTimeoutMillis: connectTimeout.inMilliseconds,
      ),
      debugName: 'alera-terminal-host-socket',
    );
  } catch (_) {
    return null;
  }
  return awaitReady();
}
