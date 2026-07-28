import 'dart:convert';
import 'dart:isolate';

import 'package:alera/src/features/browser/application/browser_engine.dart';
import 'package:alera/src/features/browser/application/browser_profile_service.dart';
import 'package:alera/src/features/browser/domain/browser_cookie_import.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:uuid/uuid.dart';

final class BrowserProfileCoordinator {
  BrowserProfileCoordinator({
    required BrowserEngine engine,
    required BrowserProfileService service,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _engine = engine, // ignore: prefer_initializing_formals
       _service = service, // ignore: prefer_initializing_formals
       _uuid = uuid, // ignore: prefer_initializing_formals
       _now = now ?? _defaultNow;

  final BrowserEngine _engine;
  final BrowserProfileService _service;
  final Uuid _uuid;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  Future<BrowserProfile> create({
    required String name,
    bool persistent = true,
  }) async {
    final id = _uuid.v4();
    final nativeProfile = await _engine.createProfile(
      id: id,
      label: name,
      kind: BrowserProfileKind.isolated,
      persistent: persistent,
    );
    if (!persistent) {
      return nativeProfile;
    }
    try {
      return await _service.upsert(id: id, name: name, persistent: persistent);
    } catch (_) {
      try {
        await _engine.deleteProfile(id);
      } on Object {
        // Preserve the catalog failure as the primary error.
      }
      rethrow;
    }
  }

  Future<bool> delete(String profileId) async {
    final profiles = await _service.list();
    final profile = profiles
        .where((value) => value.id == profileId)
        .firstOrNull;
    if (profile == null) {
      return false;
    }
    await _service.validateRemoval(profileId);
    await _engine.deleteProfile(profileId);
    try {
      final removed = await _service.remove(profileId);
      if (removed) {
        return true;
      }
      await _restoreNativeProfile(profile);
      return false;
    } catch (_) {
      await _restoreNativeProfile(profile);
      rethrow;
    }
  }

  Future<void> _restoreNativeProfile(BrowserProfile profile) async {
    try {
      await _engine.createProfile(
        id: profile.id,
        label: profile.label,
        kind: profile.kind,
        persistent: profile.persistent,
      );
    } on Object {
      // Preserve the catalog failure as the primary error.
    }
  }

  Future<List<BrowserCookieImportSourceStatus>> probeImportSources() {
    final gesture = _engine.beginCookieImportGesture();
    return _engine.probeCookieImportSources(gesture);
  }

  Future<({BrowserProfile profile, BrowserCookieImportResult result})>
  importCookies({
    required String name,
    required BrowserImportSourceFamily source,
    String? sourceProfileName,
    String? manualJson,
  }) {
    final gesture = _engine.beginCookieImportGesture();
    return _importCookiesAfterGesture(
      gesture: gesture,
      name: name,
      source: source,
      sourceProfileName: sourceProfileName,
      manualJson: manualJson,
    );
  }

  Future<({BrowserProfile profile, BrowserCookieImportResult result})>
  _importCookiesAfterGesture({
    required BrowserCookieImportGesture gesture,
    required String name,
    required BrowserImportSourceFamily source,
    String? sourceProfileName,
    String? manualJson,
  }) async {
    if (source == BrowserImportSourceFamily.manual &&
        (manualJson == null || manualJson.trim().isEmpty)) {
      throw const BrowserFailure(
        code: BrowserErrorCode.invalidPayload,
        message: 'Manual Cookie Import Requires JSON.',
        recoverable: true,
      );
    }
    if (source == BrowserImportSourceFamily.manual) {
      final byteLength = await Isolate.run(
        () => utf8.encode(manualJson!).length,
      );
      if (byteLength > browserManualCookieImportMaximumBytes) {
        throw BrowserFailure(
          code: BrowserErrorCode.invalidPayload,
          message: 'Manual Cookie Import Is Limited To 16 MiB.',
          recoverable: true,
          details: <String, Object?>{
            'maximumBytes': browserManualCookieImportMaximumBytes,
            'actualBytes': byteLength,
          },
        );
      }
    }
    if (source != BrowserImportSourceFamily.manual &&
        (sourceProfileName == null || sourceProfileName.trim().isEmpty)) {
      throw const BrowserFailure(
        code: BrowserErrorCode.invalidPayload,
        message: 'A Source Browser Profile Is Required.',
        recoverable: true,
      );
    }
    final profile = await create(name: name);
    try {
      final result = await _engine.importCookies(
        gesture: gesture,
        profileId: profile.id,
        source: source,
        sourceProfileName: sourceProfileName,
        manualJson: manualJson,
      );
      if (!result.completedAtomically) {
        throw BrowserFailure(
          code: BrowserErrorCode.unknown,
          message: 'Cookie Import Failed: ${result.outcome.name}.',
          recoverable: true,
          details: <String, Object?>{
            if (result.detailCode != null) 'detailCode': result.detailCode,
          },
        );
      }
      final importedAt = _now();
      final updated = await _service.upsert(
        id: profile.id,
        name: profile.label,
        persistent: profile.persistent,
        source: BrowserProfileSource(
          family: source,
          profileName: sourceProfileName,
          importedAt: importedAt,
        ),
      );
      return (profile: updated, result: result);
    } catch (_) {
      var catalogCleanupFailed = false;
      try {
        await _service.remove(profile.id);
      } on Object {
        catalogCleanupFailed = true;
      }
      if (!catalogCleanupFailed) {
        try {
          await _engine.deleteProfile(profile.id);
        } on Object {
          // Preserve the import failure as the primary error.
        }
      }
      rethrow;
    }
  }
}
