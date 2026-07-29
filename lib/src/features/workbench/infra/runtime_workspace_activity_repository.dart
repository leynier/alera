import 'package:alera/src/features/workbench/application/workspace_activity_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('RuntimeWorkspaceActivityRepository');

class RuntimeWorkspaceActivityRepository
    implements WorkspaceActivityRepository {
  RuntimeWorkspaceActivityRepository({
    required this.client,
    required this.legacyRepository,
    this.beforeAccess,
  });

  final RuntimeHostClient client;
  final WorkspaceActivityRepository legacyRepository;
  final Future<void> Function()? beforeAccess;

  @override
  Future<Map<String, DateTime>> loadAll() async {
    final local = await legacyRepository.loadAll();
    try {
      await beforeAccess?.call();
      final remote = _parseActivity(
        await client.runtimeRequest('workspaceActivity.list'),
      );
      final merged = <String, DateTime>{...remote};
      for (final entry in local.entries) {
        final current = merged[entry.key];
        if (current == null || entry.value.isAfter(current)) {
          merged[entry.key] = entry.value;
        }
      }
      if (local.isNotEmpty) await upsertAll(local);
      await legacyRepository.upsertAll(merged);
      return merged;
    } catch (error, stackTrace) {
      _log.warning(
        'could not merge workspace activity from the runtime; using local only',
        error,
        stackTrace,
      );
      return local;
    }
  }

  @override
  Future<void> upsertAll(Map<String, DateTime> entries) async {
    await legacyRepository.upsertAll(entries);
    await beforeAccess?.call();
    await client
        .runtimeRequest('workspaceActivity.upsertAll', <String, Object?>{
          for (final entry in entries.entries)
            entry.key: entry.value.toUtc().toIso8601String(),
        });
  }

  @override
  Future<void> remove(String workspaceId) async {
    await legacyRepository.remove(workspaceId);
    await beforeAccess?.call();
    await client.runtimeRequest('workspaceActivity.remove', <String, Object?>{
      'workspaceId': workspaceId,
    });
  }
}

Map<String, DateTime> _parseActivity(Object? value) {
  if (value is! Map) return const <String, DateTime>{};
  final result = <String, DateTime>{};
  for (final entry in value.entries) {
    if (entry.key is String && entry.value is String) {
      final parsed = DateTime.tryParse(entry.value as String);
      if (parsed != null) result[entry.key as String] = parsed.toUtc();
    }
  }
  return result;
}
