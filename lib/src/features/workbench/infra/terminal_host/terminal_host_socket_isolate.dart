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

/// Messages the isolate sends to the main isolate.
const String terminalHostIsolateReady = 'ready';
const String terminalHostIsolateLine = 'line';
const String terminalHostIsolateOutput = 'output';
const String terminalHostIsolateClosed = 'closed';
const String terminalHostIsolateError = 'error';

/// Commands the main isolate sends back.
const String terminalHostIsolateWrite = 'write';
const String terminalHostIsolateClose = 'close';

class TerminalHostSocketIsolateConfig {
  const TerminalHostSocketIsolateConfig({
    required this.host,
    required this.port,
    required this.toMain,
    required this.connectTimeoutMillis,
  });

  final String host;
  final int port;
  final SendPort toMain;
  final int connectTimeoutMillis;
}

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
  socket.setOption(SocketOption.tcpNoDelay, true);

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
      return const Utf8Decoder(
        allowMalformed: true,
      ).startChunkedConversion(StringConversionSink.fromStringSink(buffer));
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
            toMain.send(<Object?>[terminalHostIsolateLine, json]);
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
