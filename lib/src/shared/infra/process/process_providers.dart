import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/rust_process_runner.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'process_providers.g.dart';

@Riverpod(keepAlive: true)
ProcessRunner processRunner(Ref ref) {
  return const RustProcessRunner();
}

@Riverpod(keepAlive: true)
CommandEnvironmentResolver commandEnvironmentResolver(Ref ref) {
  return UserCommandEnvironmentResolver();
}
