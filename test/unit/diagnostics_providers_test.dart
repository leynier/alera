import 'dart:async';

import 'package:alera/src/features/diagnostics/application/diagnostics_providers.dart';
import 'package:alera/src/features/settings/application/runtime_settings_changes.dart';
import 'package:alera/src/features/settings/application/settings_providers.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('waits for the database before reading settings', () async {
    final databaseCompleter = Completer<AleraDatabase>();
    final database = AleraDatabase(executor: NativeDatabase.memory());
    var repositoryCreated = false;
    final container = ProviderContainer(
      overrides: [
        aleraDatabaseProvider.overrideWith((ref) => databaseCompleter.future),
        settingsRepositoryProvider.overrideWith((ref) {
          repositoryCreated = true;
          return _FakeSettingsRepository();
        }),
        runtimeSettingsChangesProvider.overrideWith(
          (ref) => const Stream<void>.empty(),
        ),
      ],
    );

    container.read(diagnosticsSettingsApplierProvider);
    expect(repositoryCreated, isFalse);

    databaseCompleter.complete(database);
    await container.read(aleraDatabaseProvider.future);
    container.read(diagnosticsSettingsApplierProvider);

    expect(repositoryCreated, isTrue);

    container.dispose();
    await database.close();
  });
}

final class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AleraSettings> load() async => AleraSettings.defaults;

  @override
  Future<void> save(AleraSettings settings) async {}
}
