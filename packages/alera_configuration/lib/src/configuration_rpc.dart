import 'configuration_transfer.dart';
import 'configuration_document.dart';
import 'configuration_sync.dart';

typedef ConfigurationRequest =
    Future<Object?> Function(String action, JsonMap payload);

class RpcConfigurationCloud implements ConfigurationCloud {
  RpcConfigurationCloud(this.request);
  final ConfigurationRequest request;
  @override
  Future<ConfigurationRevision?> head() async {
    final value = jsonMap(await request('head', {}))['head'];
    return value == null
        ? null
        : ConfigurationRevision.fromJson(jsonMap(value));
  }

  @override
  Future<List<JsonMap>> history() async =>
      (jsonMap(await request('history', {}))['revisions'] as List)
          .map(jsonMap)
          .toList();
  @override
  Future<ConfigurationRevision> revision(int revision) async =>
      ConfigurationRevision.fromJson(
        jsonMap(await request('revision', {'revision': revision})),
      );
  @override
  Future<ConfigurationRevision> publish(JsonMap operation) async =>
      ConfigurationRevision.fromJson(
        jsonMap(await request('publish', operation)),
      );
}

class RuntimeConfigurationTarget implements ConfigurationLocalTarget {
  RuntimeConfigurationTarget({
    required this.request,
    required this.accountId,
    required this.label,
  });
  final ConfigurationRequest request;
  final String accountId;
  @override
  final String label;
  @override
  Set<String> get ownedBlocks => const {'desktop', 'shared'};
  @override
  Future<ConfigurationLocalSnapshot> read() async {
    final result = await ConfigurationTransfer(request, accountId).snapshot();
    return ConfigurationLocalSnapshot(
      document: ConfigurationDocument(jsonMap(result['document'])),
      fingerprint: result['fingerprint'] as String,
      base: result['base'] == null
          ? null
          : ConfigurationRevision.fromJson(jsonMap(result['base'])),
      pending: result['pending'] == null ? null : jsonMap(result['pending']),
    );
  }

  @override
  Future<void> apply({
    required ConfigurationDocument document,
    required String expectedFingerprint,
    required ConfigurationRevision? base,
    required JsonMap? pending,
  }) async {
    await ConfigurationTransfer(request, accountId).write('apply', {
      'accountId': accountId,
      'document': document.json,
      'expectedFingerprint': expectedFingerprint,
      'base': base?.toJson(),
      'pending': pending,
    });
  }

  @override
  Future<void> published(
    String operationId,
    ConfigurationRevision revision,
  ) async {
    await ConfigurationTransfer(request, accountId).write('published', {
      'accountId': accountId,
      'operationId': operationId,
      'revision': revision.toJson(),
    });
  }
}

class ConfigurationScreenState {
  const ConfigurationScreenState({
    this.review,
    this.history = const [],
    this.error,
    this.busy = false,
  });
  final ConfigurationReview? review;
  final List<JsonMap> history;
  final String? error;
  final bool busy;
  ConfigurationScreenState copyWith({
    ConfigurationReview? review,
    List<JsonMap>? history,
    String? error,
    bool busy = false,
  }) => ConfigurationScreenState(
    review: review ?? this.review,
    history: history ?? this.history,
    error: error,
    busy: busy,
  );
}
