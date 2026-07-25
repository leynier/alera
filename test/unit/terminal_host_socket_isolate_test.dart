import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_frame_codec.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_socket_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives the isolate against a real loopback socket and collects what it
/// sends back to the main isolate.
class _IsolateHarness {
  _IsolateHarness(this.server, this.messages, this.ready);

  final ServerSocket server;
  final StreamController<List<Object?>> messages;
  final Future<Socket> ready;
}

Future<_IsolateHarness> _startIsolate() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final accepted = server.first;
  final messages = StreamController<List<Object?>>.broadcast();
  final fromIsolate = ReceivePort()
    ..listen((Object? message) {
      if (message is List) {
        messages.add(message);
      }
    });
  await Isolate.spawn<TerminalHostSocketIsolateConfig>(
    terminalHostSocketIsolateMain,
    TerminalHostSocketIsolateConfig(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      toMain: fromIsolate.sendPort,
      connectTimeoutMillis: 2000,
    ),
    debugName: 'alera-terminal-host-socket-test',
  );
  addTearDown(() async {
    fromIsolate.close();
    await messages.close();
    await server.close();
  });
  return _IsolateHarness(server, messages, accepted);
}

String _sentinelLine() {
  return '${jsonEncode(<String, Object?>{'event': terminalHostBinaryFramesEnabledLine, 'payload': const <String, Object?>{}})}\n';
}

void main() {
  test('delivers control lines before the upgrade', () async {
    final harness = await _startIsolate();
    final socket = await harness.ready;
    final line = harness.messages.stream
        .where((message) => message.first == terminalHostIsolateLine)
        .first;

    socket.write('{"id":1,"ok":true}\n');

    expect((await line)[1], '{"id":1,"ok":true}');
  });

  test('decodes output off the main isolate once framed', () async {
    final harness = await _startIsolate();
    final socket = await harness.ready;
    final output = harness.messages.stream
        .where((message) => message.first == terminalHostIsolateOutput)
        .first;

    socket.write(_sentinelLine());
    socket.add(
      encodeTerminalHostOutputFrame('session-1', utf8.encode('hola ñ')),
    );

    final message = await output;
    expect(message[1], 'session-1');
    // Text, not bytes: the UI isolate gets something it can hand to xterm.
    expect(message[2], 'hola ñ');
  });

  test('reassembles a code point split across frames', () async {
    // The reason the decoder has to live in the isolate: it is the only place
    // that sees every chunk of a session in order.
    final harness = await _startIsolate();
    final socket = await harness.ready;
    final collected = StringBuffer();
    final done = Completer<void>();
    harness.messages.stream
        .where((message) => message.first == terminalHostIsolateOutput)
        .listen((message) {
          collected.write(message[2] as String);
          if (collected.toString().endsWith('!') && !done.isCompleted) {
            done.complete();
          }
        });

    socket.write(_sentinelLine());
    final encoded = utf8.encode('ñ');
    socket.add(
      encodeTerminalHostOutputFrame('session-1', <int>[encoded.first]),
    );
    socket.add(
      encodeTerminalHostOutputFrame('session-1', <int>[encoded.last, 0x21]),
    );
    await done.future.timeout(const Duration(seconds: 5));

    expect(collected.toString(), 'ñ!');
  });

  test('reports closure when the peer goes away', () async {
    final harness = await _startIsolate();
    final socket = await harness.ready;
    final closed = harness.messages.stream
        .where((message) => message.first == terminalHostIsolateClosed)
        .first;

    await socket.close();
    socket.destroy();

    await expectLater(closed, completes);
  });

  test('a refused connection reports an error, not a hang', () async {
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = probe.port;
    await probe.close();
    final messages = StreamController<List<Object?>>.broadcast();
    final fromIsolate = ReceivePort()
      ..listen((Object? message) {
        if (message is List) {
          messages.add(message);
        }
      });
    addTearDown(() async {
      fromIsolate.close();
      await messages.close();
    });
    final error = messages.stream
        .where((message) => message.first == terminalHostIsolateError)
        .first;

    await Isolate.spawn<TerminalHostSocketIsolateConfig>(
      terminalHostSocketIsolateMain,
      TerminalHostSocketIsolateConfig(
        host: InternetAddress.loopbackIPv4.address,
        port: deadPort,
        toMain: fromIsolate.sendPort,
        connectTimeoutMillis: 1000,
      ),
      debugName: 'alera-terminal-host-socket-dead',
    );

    await expectLater(error, completes);
  });
}
