import 'package:alera/src/features/browser/application/browser_profile_coordinator.dart';
import 'package:alera/src/features/browser/application/browser_profile_service.dart';
import 'package:alera/src/features/browser/domain/browser_cookie_import.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'fake_browser_engine.dart';

void main() {
  late FakeBrowserEngine engine;
  late _FakeProfileService service;
  late BrowserProfileCoordinator coordinator;

  setUp(() {
    engine = FakeBrowserEngine();
    service = _FakeProfileService();
    coordinator = BrowserProfileCoordinator(
      engine: engine,
      service: service,
      uuid: const Uuid(),
      now: () => DateTime.utc(2026, 2, 3),
    );
  });

  tearDown(() => engine.dispose());

  test('ephemeral profiles stay outside the persistent catalog', () async {
    service.upsertError = StateError('catalog failed');

    final profile = await coordinator.create(name: 'Work', persistent: false);

    expect(profile.persistent, isFalse);
    expect(engine.calls.any((call) => call.endsWith(':false')), isTrue);
    expect(service.upserts, isEmpty);
    expect(
      engine.calls.any((call) => call.startsWith('deleteProfile:')),
      isFalse,
    );
  });

  test(
    'rolls native persistent profile back when catalog create fails',
    () async {
      service.upsertError = StateError('catalog failed');

      await expectLater(coordinator.create(name: 'Work'), throwsStateError);

      expect(
        engine.calls.any((call) => call.startsWith('deleteProfile:')),
        isTrue,
      );
    },
  );

  test('leaves the catalog untouched when native delete fails', () async {
    final profile = _profile(
      source: BrowserProfileSource(
        family: .chrome,
        profileName: 'Profile 1',
        importedAt: .utc(2026, 1, 1),
      ),
    );
    service.profiles.add(profile);
    engine.deleteProfileError = StateError('native failed');

    await expectLater(coordinator.delete(profile.id), throwsStateError);

    expect(service.validated, contains(profile.id));
    expect(service.removed, isEmpty);
    expect(service.profiles, contains(profile));
  });

  test('validates before native and catalog deletion', () async {
    final profile = _profile();
    service.profiles.add(profile);

    expect(await coordinator.delete(profile.id), isTrue);

    expect(service.calls, <String>[
      'list',
      'validateRemoval:${profile.id}',
      'remove:${profile.id}',
    ]);
    expect(
      engine.calls.where((call) => call == 'deleteProfile:${profile.id}'),
      hasLength(1),
    );
  });

  test('does not touch native storage when removal validation fails', () async {
    final profile = _profile();
    service.profiles.add(profile);
    service.validateRemovalError = StateError('profile in use');

    await expectLater(coordinator.delete(profile.id), throwsStateError);

    expect(
      engine.calls.any((call) => call.startsWith('deleteProfile:')),
      isFalse,
    );
    expect(service.removed, isEmpty);
  });

  test('recreates native partition when catalog commit fails', () async {
    final profile = _profile();
    service.profiles.add(profile);
    service.removeError = StateError('catalog failed');

    await expectLater(coordinator.delete(profile.id), throwsStateError);

    expect(
      engine.calls.where((call) => call == 'deleteProfile:${profile.id}'),
      hasLength(1),
    );
    expect(
      engine.calls.any(
        (call) => call.startsWith('createProfile:${profile.id}:'),
      ),
      isTrue,
    );
    expect(service.profiles, contains(profile));
  });

  test('partial imports fail and compensate both stores', () async {
    engine.importResult = const BrowserCookieImportResult(
      source: .chrome,
      profileId: 'ignored',
      outcome: .partiallyImported,
      importedCount: 2,
      skippedCount: 1,
    );

    await expectLater(
      coordinator.importCookies(
        name: 'Imported',
        source: .chrome,
        sourceProfileName: 'Profile 1',
      ),
      throwsA(anything),
    );

    expect(service.removed, isNotEmpty);
    expect(
      engine.calls.where((call) => call.startsWith('deleteProfile:')),
      isNotEmpty,
    );
    expect(service.upserts.where((profile) => profile.source != null), isEmpty);
  });

  test(
    'keeps native storage when failed catalog cleanup may leave its row',
    () async {
      service.sourceUpsertError = StateError('metadata failed');
      service.removeError = StateError('catalog cleanup failed');

      await expectLater(
        coordinator.importCookies(
          name: 'Imported',
          source: .chrome,
          sourceProfileName: 'Profile 1',
        ),
        throwsStateError,
      );

      expect(service.profiles, hasLength(1));
      final profileId = service.profiles.single.id;
      expect(
        engine.calls.where((call) => call == 'deleteProfile:$profileId'),
        isEmpty,
      );
    },
  );

  test('native import requires a selected source profile', () async {
    await expectLater(
      coordinator.importCookies(name: 'Imported', source: .chrome),
      throwsA(
        isA<BrowserFailure>().having(
          (failure) => failure.code,
          'code',
          BrowserErrorCode.invalidPayload,
        ),
      ),
    );

    expect(engine.calls, isEmpty);
    expect(service.upserts, isEmpty);
  });

  test(
    'manual import rejects payloads over 16 MiB before profile creation',
    () async {
      final oversized = ''.padRight(
        browserManualCookieImportMaximumBytes + 1,
        'x',
      );

      await expectLater(
        coordinator.importCookies(
          name: 'Imported',
          source: .manual,
          manualJson: oversized,
        ),
        throwsA(
          isA<BrowserFailure>().having(
            (failure) => failure.code,
            'code',
            BrowserErrorCode.invalidPayload,
          ),
        ),
      );

      expect(engine.calls, isEmpty);
      expect(service.upserts, isEmpty);
    },
  );

  test('selected source profile is imported and saved as metadata', () async {
    final imported = await coordinator.importCookies(
      name: 'Imported',
      source: .chrome,
      sourceProfileName: 'Profile 1',
    );

    expect(imported.profile.source?.profileName, 'Profile 1');
    expect(
      engine.calls.any(
        (call) =>
            call.startsWith('importCookies:') &&
            call.endsWith(':chrome:Profile 1'),
      ),
      isTrue,
    );
  });
}

final class _FakeProfileService implements BrowserProfileService {
  final List<BrowserProfile> profiles = <BrowserProfile>[];
  final List<BrowserProfile> upserts = <BrowserProfile>[];
  final List<String> removed = <String>[];
  final List<String> validated = <String>[];
  final List<String> calls = <String>[];
  Object? upsertError;
  Object? sourceUpsertError;
  Object? validateRemovalError;
  Object? removeError;

  @override
  Future<List<BrowserProfile>> list() async {
    calls.add('list');
    return List<BrowserProfile>.of(profiles);
  }

  @override
  Stream<List<BrowserProfile>> watchAll() => Stream.value(profiles);

  @override
  Future<BrowserProfile> upsert({
    String? id,
    required String name,
    bool persistent = true,
    BrowserProfileSource? source,
  }) async {
    if (upsertError case final error?) {
      throw error;
    }
    if (source != null) {
      final error = sourceUpsertError;
      if (error != null) {
        throw error;
      }
    }
    final profile = BrowserProfile(
      id: id ?? 'profile',
      label: name,
      kind: .isolated,
      persistent: persistent,
      createdAt: .utc(2026),
      source: source,
    );
    upserts.add(profile);
    profiles
      ..removeWhere((value) => value.id == profile.id)
      ..add(profile);
    return profile;
  }

  @override
  Future<void> validateRemoval(String profileId) async {
    calls.add('validateRemoval:$profileId');
    validated.add(profileId);
    if (validateRemovalError case final error?) {
      throw error;
    }
  }

  @override
  Future<bool> remove(String profileId) async {
    calls.add('remove:$profileId');
    if (removeError case final error?) {
      throw error;
    }
    removed.add(profileId);
    profiles.removeWhere((profile) => profile.id == profileId);
    return true;
  }
}

BrowserProfile _profile({BrowserProfileSource? source}) {
  return BrowserProfile(
    id: 'work',
    label: 'Work',
    kind: .imported,
    createdAt: .utc(2026),
    source: source,
  );
}
