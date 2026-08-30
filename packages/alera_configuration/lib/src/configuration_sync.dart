import 'dart:math';
import 'dart:isolate';
import 'configuration_document.dart';
import 'configuration_merge.dart';
import 'portable_settings.dart';
import 'configuration_history.dart';

abstract interface class ConfigurationCloud {
  Future<ConfigurationRevision?> head();
  Future<List<JsonMap>> history();
  Future<ConfigurationRevision> revision(int revision);
  Future<ConfigurationRevision> publish(JsonMap operation);
}

class ConfigurationLocalSnapshot {
  ConfigurationLocalSnapshot({
    required this.document,
    required this.fingerprint,
    this.base,
    this.pending,
  });
  final ConfigurationDocument document;
  final String fingerprint;
  final ConfigurationRevision? base;
  final JsonMap? pending;
}

abstract interface class ConfigurationLocalTarget {
  String get label;
  Set<String> get ownedBlocks;
  Future<ConfigurationLocalSnapshot> read();
  Future<void> apply({
    required ConfigurationDocument document,
    required String expectedFingerprint,
    required ConfigurationRevision? base,
    required JsonMap? pending,
  });
  Future<void> published(String operationId, ConfigurationRevision revision);
}

class ConfigurationReview {
  ConfigurationReview(this.local, this.head, this.source, this.merge);
  final ConfigurationLocalSnapshot local;
  final ConfigurationRevision? head;
  final ConfigurationRevision? source;
  final ConfigurationMerge merge;
}

class ConfigurationSyncService {
  ConfigurationSyncService({
    required this.cloud,
    required this.target,
    this.retain,
  });
  final ConfigurationCloud cloud;
  final ConfigurationLocalTarget target;
  final void Function() Function()? retain;

  Future<ConfigurationReview> review({int? historicalRevision}) async {
    final head = await cloud.head();
    final source = historicalRevision == null
        ? head
        : await cloud.revision(historicalRevision);
    final local = await target.read();
    final remote = source?.document ?? ConfigurationDocument.empty();
    // An old revision supplies only supported blocks. Preserve today's opaque data.
    final input = head != null && historicalRevision != null
        ? configurationForRestore(head.document, remote, target.ownedBlocks)
        : head == null
        ? remote
        : head.document.withBlocks({
            for (final block in target.ownedBlocks) block: remote.json[block],
          });
    final ownedBlocks = target.ownedBlocks;
    final merge = await Isolate.run(
      () => ConfigurationMerge(
        local: local.document,
        remote: input,
        base: local.base?.document,
        ownedBlocks: ownedBlocks,
      ),
    );
    return ConfigurationReview(local, head, source, merge);
  }

  Future<void> apply(ConfigurationReview review, {required bool upload}) async {
    final merge = review.merge;
    final ownedBlocks = target.ownedBlocks;
    final document = await Isolate.run(() {
      final result = merge.resolve();
      final errors = validateConfiguration(result, ownedBlocks: ownedBlocks);
      if (errors.isNotEmpty) throw StateError(errors.join('\n'));
      return result;
    });
    final current = await cloud.head();
    if (current?.revision != review.head?.revision) {
      throw StateError(
        'The shared configuration changed. Review the latest version.',
      );
    }
    final operation = upload
        ? <String, Object?>{
            'operationId': _operationId(),
            'expectedRevision': current?.revision,
            'document': document.json,
            'deviceName': target.label,
            'summary':
                '${review.merge.differences.length} configuration differences',
          }
        : null;
    await target.apply(
      document: document,
      expectedFingerprint: review.local.fingerprint,
      base: current,
      pending: operation,
    );
    if (operation != null) await _publish(operation);
  }

  Future<void> retryPending() async {
    final local = await target.read();
    if (local.pending == null) throw StateError('No pending upload.');
    await _publish(local.pending!);
  }

  Future<ConfigurationReview> recoverReview(
    ConfigurationReview previous,
  ) async {
    final local = await target.read();
    try {
      final head = await cloud.head();
      if (local.fingerprint != previous.local.fingerprint ||
          head?.revision != previous.head?.revision) {
        return await review(
          historicalRevision:
              previous.source?.revision != previous.head?.revision
              ? previous.source?.revision
              : null,
        );
      }
    } catch (_) {
      // A failed upload must remain retryable even while Cloud is unavailable.
    }
    // Never attach a new fingerprint to an old proposal: that would bypass CAS.
    return ConfigurationReview(
      ConfigurationLocalSnapshot(
        document: previous.local.document,
        fingerprint: previous.local.fingerprint,
        base: previous.local.base,
        pending: local.pending,
      ),
      previous.head,
      previous.source,
      previous.merge,
    );
  }

  Future<void> _publish(JsonMap operation) async {
    final revision = await cloud.publish(operation);
    await target.published(operation['operationId'] as String, revision);
  }
}

String _operationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
