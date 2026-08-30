import 'package:url_launcher/url_launcher.dart' as url_launcher;

typedef UriLaunchCallback = Future<bool> Function(Uri uri);

abstract interface class ExternalUriLauncher {
  Future<void> open(Uri uri);
}

class UrlLauncherExternalUriLauncher({UriLaunchCallback? launch})
    implements ExternalUriLauncher {
  this : _launch = launch ?? _launchExternalUri;

  final UriLaunchCallback _launch;

  @override
  Future<void> open(Uri uri) async {
    if (!await _launch(uri)) {
      throw StateError('Could not open URI: $uri');
    }
  }
}

Future<bool> _launchExternalUri(Uri uri) {
  return url_launcher.launchUrl(
    uri,
    mode: url_launcher.LaunchMode.externalApplication,
  );
}
