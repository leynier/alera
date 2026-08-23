import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const mobileExternalBrowserChannelName = 'dev.leynier.alera/external_browser';

/// Opens [url] in the device's standalone browser, not a Custom Tab.
///
/// Android's default `ACTION_VIEW` can land in Chrome Custom Tabs or a
/// host-specific in-app browser (GitHub for APK links). The native channel
/// forces a real browser in its own task. url_launcher remains the fallback
/// for tests and for a host without that channel.
Future<bool> openMobileExternalBrowser(
  Uri url, {
  MethodChannel? channel,
  Future<bool> Function(Uri url)? fallback,
}) async {
  if (!url.isScheme('http') && !url.isScheme('https')) {
    return false;
  }
  try {
    final opened =
        await (channel ?? const MethodChannel(mobileExternalBrowserChannelName))
            .invokeMethod<bool>('open', <String, Object>{
              'url': url.toString(),
            });
    if (opened == true) {
      return true;
    }
  } on MissingPluginException {
    // Widget tests and platforms without the Android channel.
  } on PlatformException {
    // Native refused the URL; try the generic launcher next.
  }
  final launch = fallback ?? _launchUrlLauncherExternal;
  return launch(url);
}

Future<bool> _launchUrlLauncherExternal(Uri url) {
  return launchUrl(url, mode: LaunchMode.externalApplication);
}
