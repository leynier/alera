import 'package:alera_configuration/alera_configuration.dart';
import 'package:test/test.dart';

ConfigurationDocument doc(int font) =>
    ConfigurationDocument.empty().withBlocks({
      'desktop': {'font': font},
    });

class Cloud implements ConfigurationCloud {
  ConfigurationRevision? current;
  ConfigurationRevision? historical;
  bool loseResponse = false;
  bool offline = false;
  int writes = 0;
  final operations = <String, ConfigurationRevision>{};
  @override
  Future<ConfigurationRevision?> head() async {
    if (offline) throw StateError('Offline');
    return current;
  }

  @override
  Future<List<JsonMap>> history() async => [];
  @override
  Future<ConfigurationRevision> revision(int value) async =>
      historical ?? current!;
  @override
  Future<ConfigurationRevision> publish(JsonMap operation) async {
    final id = operation['operationId'] as String;
    if (operations.containsKey(id)) return operations[id]!;
    if (current?.revision != operation['expectedRevision'])
      throw StateError('Conflict');
    current = ConfigurationRevision(
      revision: (current?.revision ?? 0) + 1,
      document: ConfigurationDocument(jsonMap(operation['document'])),
    );
    operations[id] = current!;
    writes++;
    if (loseResponse) {
      loseResponse = false;
      throw StateError('Lost response');
    }
    return current!;
  }
}

class Target implements ConfigurationLocalTarget {
  ConfigurationDocument document = doc(12);
  ConfigurationDocument? backup;
  ConfigurationRevision? base;
  JsonMap? pending;
  @override
  String get label => 'Device';
  @override
  Set<String> get ownedBlocks => {'desktop'};
  @override
  Future<ConfigurationLocalSnapshot> read() async => ConfigurationLocalSnapshot(
    document: document,
    fingerprint: document.digest,
    base: base,
    pending: pending,
  );
  @override
  Future<void> apply({
    required ConfigurationDocument document,
    required String expectedFingerprint,
    required ConfigurationRevision? base,
    required JsonMap? pending,
  }) async {
    if (expectedFingerprint != this.document.digest)
      throw StateError('Local changed');
    backup = this.document;
    this.document = document;
    this.base = base;
    this.pending = pending;
  }

  @override
  Future<void> published(
    String operationId,
    ConfigurationRevision revision,
  ) async {
    if (pending?['operationId'] != operationId)
      throw StateError('Pending changed');
    base = revision;
    pending = null;
  }
}

void main() {
  test(
    'restoring history preserves newer opaque fields and appends a revision',
    () async {
      final old = ConfigurationRevision(
        revision: 1,
        document: ConfigurationDocument.empty().withBlocks({
          'desktop': {
            'settings': {
              'terminal': {'fontSize': 12.0},
            },
          },
        }),
      );
      final latest = ConfigurationRevision(
        revision: 3,
        document: ConfigurationDocument.empty().withBlocks({
          'desktop': {
            'future': true,
            'settings': {
              'terminal': {'fontSize': 20.0, 'futureField': 'keep'},
              'futureSection': [1],
            },
          },
          'mobile': {'futurePhoneSetting': true},
        }),
      );
      final cloud = Cloud()
        ..current = latest
        ..historical = old;
      final target = Target()
        ..document = latest.document
        ..base = latest;
      final sync = ConfigurationSyncService(cloud: cloud, target: target);
      final review = await sync.review(historicalRevision: 1);
      review.merge.chooseAll(ConfigurationChoice.remote);
      await sync.apply(review, upload: true);
      expect(cloud.current!.revision, 4);
      final desktop = jsonMap(target.document.json['desktop']);
      expect(desktop['future'], true);
      expect(jsonMap(desktop['settings'])['terminal'], {
        'fontSize': 12.0,
        'futureField': 'keep',
      });
      expect(jsonMap(desktop['settings'])['futureSection'], [1]);
      expect(target.document.json['mobile'], {'futurePhoneSetting': true});
    },
  );
  test(
    'error recovery never gives an old proposal a new fingerprint',
    () async {
      final cloud = Cloud();
      final target = Target();
      final sync = ConfigurationSyncService(cloud: cloud, target: target);
      final original = await sync.review();
      target.document = doc(22);
      target.pending = {'operationId': 'pending'};
      cloud.offline = true;
      final recovered = await sync.recoverReview(original);
      expect(recovered.local.fingerprint, original.local.fingerprint);
      expect(recovered.local.pending, target.pending);
      cloud.offline = false;
      await expectLater(sync.apply(recovered, upload: false), throwsStateError);
      expect(target.document.json['desktop'], {'font': 22});
      final refreshed = await sync.recoverReview(recovered);
      expect(refreshed.merge.resolve().json['desktop'], {'font': 22});
    },
  );
  test('review and cancellation are read-only; pull never publishes', () async {
    final cloud = Cloud()
      ..current = ConfigurationRevision(revision: 1, document: doc(16));
    final target = Target();
    final sync = ConfigurationSyncService(cloud: cloud, target: target);
    final review = await sync.review();
    expect(target.document.json['desktop'], {'font': 12});
    expect(target.base, isNull);
    review.merge.chooseAll(ConfigurationChoice.remote);
    await sync.apply(review, upload: false);
    expect(target.document.json['desktop'], {'font': 16});
    expect(cloud.writes, 0);
    expect(target.backup!.json['desktop'], {'font': 12});
  });
  test(
    'lost publication response can retry without duplicate revision or losing later local edits',
    () async {
      final cloud = Cloud()..loseResponse = true;
      final target = Target();
      final sync = ConfigurationSyncService(cloud: cloud, target: target);
      final review = await sync.review();
      await expectLater(sync.apply(review, upload: true), throwsStateError);
      expect(target.pending, isNotNull);
      target.document = doc(20);
      await sync.retryPending();
      expect(cloud.writes, 1);
      expect(target.pending, isNull);
      expect(target.document.json['desktop'], {'font': 20});
      expect(target.base!.document.json['desktop'], {'font': 12});
    },
  );
  test(
    'remote and local races invalidate an already prepared review',
    () async {
      final cloud = Cloud();
      final target = Target();
      final sync = ConfigurationSyncService(cloud: cloud, target: target);
      final review = await sync.review();
      cloud.current = ConfigurationRevision(revision: 1, document: doc(18));
      await expectLater(sync.apply(review, upload: true), throwsStateError);
      expect(target.backup, isNull);
      cloud.current = null;
      target.document = doc(14);
      await expectLater(sync.apply(review, upload: false), throwsStateError);
      expect(target.backup, isNull);
    },
  );
}
