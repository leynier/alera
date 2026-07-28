import 'dart:io';

import 'package:alera_mobile/src/features/updater/domain/mobile_release.dart';
import 'package:alera_mobile/src/features/updater/infra/github_mobile_release_source.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'mobile_update_providers.g.dart';

@Riverpod(keepAlive: true)
GitHubMobileReleaseSource mobileReleaseSource(Ref ref) {
  final source = GitHubMobileReleaseSource();
  ref.onDispose(source.dispose);
  return source;
}

/// The newest release worth offering, or null when the app is current.
///
/// This resolves once per launch: it is `keepAlive`, so returning to a screen
/// that watches it does not spend another GitHub API call.
@Riverpod(keepAlive: true)
Future<MobileRelease?> availableMobileUpdate(Ref ref) async {
  // Only Android has a published build to install; iOS is not shipped yet.
  if (!Platform.isAndroid) {
    return null;
  }
  final info = await PackageInfo.fromPlatform();
  final current = MobileVersion.tryParse(info.version);
  if (current == null) {
    return null;
  }
  try {
    final latest = await ref.watch(mobileReleaseSourceProvider).latestRelease();
    if (latest == null || !latest.version.isNewerThan(current)) {
      return null;
    }
    return latest;
  } on http.ClientException {
    // A rate-limited or offline check is not worth interrupting a launch over.
    return null;
  } on FormatException {
    return null;
  } on SocketException {
    return null;
  }
}
