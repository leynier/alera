import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'process_providers.g.dart';

@Riverpod(keepAlive: true)
ProcessRunner processRunner(Ref ref) {
  return const IoProcessRunner();
}
