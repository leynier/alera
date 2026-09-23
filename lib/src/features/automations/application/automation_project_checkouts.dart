import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'automation_project_checkouts.g.dart';

@riverpod
Future<List<({String hostId, String path})>> automationProjectCheckouts(
  Ref ref,
  String projectId,
) async {
  if (projectId.isEmpty) return const [];
  final result = await ref.watch(runtimeHostClientProvider).runtimeRequest(
    'checkout.list',
    <String, Object?>{'projectId': projectId},
  );
  if (result is! List) throw StateError('Could not load project folders.');
  return projectFolderChoices(result);
}

List<({String hostId, String path})> projectFolderChoices(
  List<Object?> checkouts,
) => [
  for (final item in checkouts)
    if ((item as Map)['kind'] == 'project')
      (hostId: item['hostId'] as String, path: item['path'] as String),
];
