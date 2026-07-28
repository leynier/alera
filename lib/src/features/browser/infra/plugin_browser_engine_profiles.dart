part of 'plugin_browser_engine.dart';

final class _PluginBrowserProfiles {
  _PluginBrowserProfiles({
    required AleraBrowserClient client,
    required DateTime Function() now,
  }) : _client = client, // ignore: prefer_initializing_formals
       _now = now; // ignore: prefer_initializing_formals

  final AleraBrowserClient _client;
  final DateTime Function() _now;
  final Map<String, AleraBrowserUserGestureToken> _importGestures =
      <String, AleraBrowserUserGestureToken>{};
  var _gestureSequence = 0;

  Future<List<BrowserProfile>> list() {
    return _run(() async {
      final values = await _client.listProfiles();
      final now = _now();
      return <BrowserProfile>[
        for (final value in values)
          BrowserProfile(
            id: value.id,
            label: value.id,
            kind: value.isDefault
                ? BrowserProfileKind.defaultProfile
                : BrowserProfileKind.isolated,
            persistent: value.storage == AleraBrowserProfileStorage.persistent,
            createdAt: now,
          ),
      ];
    });
  }

  Future<BrowserProfile> create({
    required String id,
    required String label,
    required BrowserProfileKind kind,
    required bool persistent,
  }) {
    return _run(() async {
      final value = await _client.createProfile(
        AleraBrowserProfileOptions(
          id: id,
          storage: persistent
              ? AleraBrowserProfileStorage.persistent
              : AleraBrowserProfileStorage.ephemeral,
        ),
      );
      return BrowserProfile(
        id: value.id,
        label: label,
        kind: value.isDefault ? BrowserProfileKind.defaultProfile : kind,
        persistent: value.storage == AleraBrowserProfileStorage.persistent,
        createdAt: _now(),
      );
    });
  }

  Future<void> delete(String profileId) =>
      _run(() => _client.deleteProfile(profileId));

  BrowserCookieImportGesture beginImportGesture() {
    final issuedAt = _now();
    final id = '${++_gestureSequence}';
    _importGestures[id] = _client.beginCookieImportGesture();
    return BrowserCookieImportGesture(id: id, issuedAt: issuedAt);
  }

  Future<List<BrowserCookieImportSourceStatus>> probeImportSources(
    BrowserCookieImportGesture gesture,
  ) {
    return _run(() async {
      final token = _consumeImportGesture(gesture);
      final values = await _client.probeCookieImportSources(token);
      return <BrowserCookieImportSourceStatus>[
        for (final value in values)
          BrowserCookieImportSourceStatus(
            source: _importSourceFromPlugin(value.source),
            supported: value.supported,
            available: value.available,
            profileNames: List<String>.unmodifiable(value.profileNames),
            detailCode: value.detailCode,
          ),
      ];
    });
  }

  Future<BrowserCookieImportResult> import({
    required BrowserCookieImportGesture gesture,
    required String profileId,
    required BrowserImportSourceFamily source,
    String? sourceProfileName,
    String? manualJson,
  }) {
    return _run(() async {
      final token = _consumeImportGesture(gesture);
      final pluginSource = _importSourceToPlugin(source);
      if (pluginSource != AleraBrowserCookieImportSource.manualJson &&
          (sourceProfileName == null || sourceProfileName.trim().isEmpty)) {
        throw const BrowserFailure(
          code: BrowserErrorCode.invalidPayload,
          message: 'A Source Browser Profile Is Required.',
          recoverable: true,
        );
      }
      final request = pluginSource == AleraBrowserCookieImportSource.manualJson
          ? AleraBrowserManualCookieImportRequest(
              profileId: profileId,
              gestureToken: token,
              json: manualJson ?? '',
            )
          : AleraBrowserNativeCookieImportRequest(
              profileId: profileId,
              gestureToken: token,
              source: pluginSource,
              sourceProfileName: sourceProfileName!,
            );
      final value = await _client.importCookies(request);
      return BrowserCookieImportResult(
        source: _importSourceFromPlugin(value.source),
        profileId: value.profileId,
        outcome: BrowserCookieImportOutcome.values.byName(value.outcome.name),
        importedCount: value.importedCount,
        skippedCount: value.skippedCount,
        detailCode: value.detailCode,
      );
    });
  }

  AleraBrowserUserGestureToken _consumeImportGesture(
    BrowserCookieImportGesture gesture,
  ) {
    final token = _importGestures.remove(gesture.id);
    if (token == null) {
      throw const BrowserFailure(
        code: BrowserErrorCode.permissionDenied,
        message: 'Cookie Import Requires A Fresh User Gesture.',
      );
    }
    return token;
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on BrowserFailure {
      rethrow;
    } on AleraBrowserException catch (error) {
      throw _failureFromPlugin(error);
    }
  }
}
