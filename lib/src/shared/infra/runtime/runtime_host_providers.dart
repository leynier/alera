import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'runtime_host_providers.g.dart';

@Riverpod(keepAlive: true)
SocketTerminalHostClient runtimeHostClient(Ref ref) {
  final client = SocketTerminalHostClient();
  ref.onDispose(client.dispose);
  return client;
}
