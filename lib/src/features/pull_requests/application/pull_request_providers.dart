import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/features/pull_requests/application/forge_provider_registry.dart';
import 'package:alera/src/features/pull_requests/application/linked_review_repository.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';
import 'package:alera/src/features/pull_requests/infra/azure_devops_forge_provider.dart';
import 'package:alera/src/features/pull_requests/infra/github_forge_provider.dart';
import 'package:alera/src/features/pull_requests/infra/runtime_linked_review_repository.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pull_request_providers.g.dart';

@Riverpod(keepAlive: true)
GitHubForgeProvider githubForgeProvider(Ref ref) {
  return GitHubForgeProvider(ref.watch(processRunnerProvider));
}

@Riverpod(keepAlive: true)
AzureDevOpsForgeProvider azureDevOpsForgeProvider(Ref ref) {
  return AzureDevOpsForgeProvider(ref.watch(processRunnerProvider));
}

@Riverpod(keepAlive: true)
ForgeProviderRegistry forgeProviderRegistry(Ref ref) {
  return ForgeProviderRegistry(<ForgeProvider>[
    ref.watch(githubForgeProviderProvider),
    ref.watch(azureDevOpsForgeProviderProvider),
  ]);
}

@Riverpod(keepAlive: true)
LinkedReviewRepository linkedReviewRepository(Ref ref) {
  return RuntimeLinkedReviewRepository(
    ref.watch(runtimeHostClientProvider),
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
  );
}

/// The effective git-hosting-provider override for a project (UI override or
/// repo `alera.toml`), or null when the project should auto-detect. Feeds the
/// per-workspace pull-request scope.
@Riverpod(keepAlive: true)
Future<GitHostingProvider?> effectiveHostingProviderOverride(
  Ref ref,
  String projectId,
) async {
  final projects = await ref.watch(projectListProvider.future);
  Project? project;
  for (final candidate in projects) {
    if (candidate.id == projectId) {
      project = candidate;
      break;
    }
  }
  if (project == null) {
    return null;
  }
  final effective = await ref
      .watch(projectConfigServiceProvider)
      .resolve(project);
  return effective.config.gitHostingProvider;
}
