import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'configuration_document.dart';
import 'configuration_rpc.dart';

const configurationTransferMaxBytes = 2 * 1024 * 1024;
const _chunkBytes = 128 * 1024;

/// Keeps configuration bundles below the terminal relay's unchanged envelope cap.
class ConfigurationTransfer {
  ConfigurationTransfer(this.request, this.accountId);
  final ConfigurationRequest request;
  final String accountId;

  Future<JsonMap> snapshot() async {
    final meta = jsonMap(
      await request('configuration.transfer.start', {
        'accountId': accountId,
        'action': 'snapshot',
      }),
    );
    final size = meta['size'];
    if (size is! int || size <= 0 || size > configurationTransferMaxBytes) {
      throw const FormatException('Invalid configuration transfer size.');
    }
    final id = meta['transferId'] as String;
    final bytes = BytesBuilder(copy: false);
    try {
      while (bytes.length < size) {
        final response = jsonMap(
          await request('configuration.transfer.read', {
            'accountId': accountId,
            'transferId': id,
            'offset': bytes.length,
          }),
        );
        final data = response['data'] as String;
        if (data.length > ((_chunkBytes + 2) ~/ 3) * 4) {
          throw const FormatException('Configuration chunk is too large.');
        }
        final chunk = base64Decode(data);
        if (chunk.isEmpty ||
            chunk.length > _chunkBytes ||
            bytes.length + chunk.length > size) {
          throw const FormatException('Invalid configuration chunk.');
        }
        bytes.add(chunk);
      }
      final encoded = bytes.takeBytes();
      return await Isolate.run(() => jsonMap(jsonDecode(utf8.decode(encoded))));
    } finally {
      await _cancel(id);
    }
  }

  Future<void> write(String action, JsonMap payload) async {
    final bytes = await Isolate.run(() => utf8.encode(jsonEncode(payload)));
    if (bytes.length > configurationTransferMaxBytes) {
      throw const FormatException('Configuration transfer exceeds its limit.');
    }
    final meta = jsonMap(
      await request('configuration.transfer.start', {
        'accountId': accountId,
        'action': action,
        'size': bytes.length,
      }),
    );
    final id = meta['transferId'] as String;
    try {
      for (var offset = 0; offset < bytes.length; offset += _chunkBytes) {
        final end = (offset + _chunkBytes).clamp(0, bytes.length);
        await request('configuration.transfer.chunk', {
          'accountId': accountId,
          'transferId': id,
          'offset': offset,
          'data': base64Encode(bytes.sublist(offset, end)),
        });
      }
      await request('configuration.transfer.commit', {
        'accountId': accountId,
        'transferId': id,
      });
    } finally {
      await _cancel(id);
    }
  }

  Future<void> _cancel(String id) async {
    try {
      await request('configuration.transfer.cancel', {
        'accountId': accountId,
        'transferId': id,
      });
    } catch (_) {
      // A committed, expired, or disconnected transfer no longer needs cleanup.
    }
  }
}
