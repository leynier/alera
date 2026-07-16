import 'package:alera/src/features/workbench/application/repository_browser_opener.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:alera/src/shared/infra/uri/uri_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'repository_browser_providers.g.dart';

@Riverpod(keepAlive: true)
RepositoryBrowserOpener repositoryBrowserOpener(Ref ref) {
  return RepositoryBrowserOpener(
    gitBackend: ref.watch(gitBackendProvider),
    launcher: ref.watch(externalUriLauncherProvider),
    processRunner: ref.watch(processRunnerProvider),
  );
}
