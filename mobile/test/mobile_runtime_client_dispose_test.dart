import 'dart:async';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test(
    'Dispose does not wait forever for a transport close handshake',
    () async {
      final channel = _HangingCloseWebSocketChannel();
      final client = MobileRuntimeClient.forTesting(
        channel,
        transportCloseTimeout: const Duration(milliseconds: 20),
      );

      await client.dispose().timeout(const Duration(seconds: 1));

      expect(channel.closeCalled, isTrue);
    },
  );
}

final class _HangingCloseWebSocketChannel
    with StreamChannelMixin<Object?>
    implements WebSocketChannel {
  final StreamController<Object?> _incoming = StreamController<Object?>();
  final Completer<void> _close = Completer<void>();

  bool closeCalled = false;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<Object?> get stream => _incoming.stream;

  @override
  late final WebSocketSink sink = _HangingCloseWebSocketSink(this);
}

final class _HangingCloseWebSocketSink implements WebSocketSink {
  _HangingCloseWebSocketSink(this.channel);

  final _HangingCloseWebSocketChannel channel;

  @override
  Future<void> get done => channel._close.future;

  @override
  void add(Object? data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<Object?> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    channel.closeCalled = true;
    return channel._close.future;
  }
}
