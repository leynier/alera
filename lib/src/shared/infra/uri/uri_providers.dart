import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'uri_providers.g.dart';

@Riverpod(keepAlive: true)
ExternalUriLauncher externalUriLauncher(Ref ref) {
  return UrlLauncherExternalUriLauncher();
}
