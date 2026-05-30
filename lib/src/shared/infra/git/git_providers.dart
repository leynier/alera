import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/rust_git_backend.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'git_providers.g.dart';

@Riverpod(keepAlive: true)
GitBackend gitBackend(Ref ref) {
  return const RustGitBackend();
}
