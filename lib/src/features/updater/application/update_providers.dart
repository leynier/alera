import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/infra/desktop_update_service.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'update_providers.g.dart';

@Riverpod(keepAlive: true)
http.Client aleraUpdateHttpClient(Ref ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
}

@Riverpod(keepAlive: true)
AleraUpdateService aleraUpdateService(Ref ref) {
  final service = DesktopAleraUpdateService(
    client: ref.watch(aleraUpdateHttpClientProvider),
  );
  ref.onDispose(service.dispose);
  return service;
}
