import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'runtime_host_providers.g.dart';

@Riverpod(keepAlive: true)
SocketTerminalHostClient runtimeHostClient(Ref ref) {
  final client = SocketTerminalHostClient();
  ref.onDispose(client.dispose);
  return client;
}

/// One coalescer for every runtime watcher, keyed by namespaced strings
/// (`tabs:<id>`, `workspaces:<id>`, `projects`, ...), so there is a single
/// place to instrument and tune how change events fan out into RPC.
@Riverpod(keepAlive: true)
RuntimeChangeCoalescer runtimeChangeCoalescer(Ref ref) {
  final coalescer = RuntimeChangeCoalescer();
  ref.onDispose(coalescer.dispose);
  return coalescer;
}
