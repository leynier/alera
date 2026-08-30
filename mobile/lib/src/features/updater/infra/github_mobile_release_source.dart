import 'dart:convert';

import 'package:alera_mobile/src/features/updater/domain/mobile_release.dart';
import 'package:http/http.dart' as http;

/// The releases listing, not `/releases/latest`: that endpoint resolves to the
/// newest desktop release, and mobile ships on its own tag sequence.
final Uri defaultMobileReleasesUrl = Uri.parse(
  'https://api.github.com/repos/leynier/alera/releases?per_page=30',
);

/// Finds the newest published Android build on GitHub Releases.
class GitHubMobileReleaseSource({http.Client? client, Uri? releasesUrl}) {
  this
    : _client = client ?? http.Client(),
      _releasesUrl = releasesUrl ?? defaultMobileReleasesUrl,
      _ownsClient = client == null;

  final http.Client _client;
  final Uri _releasesUrl;
  final bool _ownsClient;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsClient) _client.close();
  }

  Future<MobileRelease?> latestRelease() async {
    if (_disposed) return null;
    late final http.Response response;
    try {
      response = await _client.get(
        _releasesUrl,
        headers: const <String, String>{
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
    } on http.ClientException {
      // Closing an owned IOClient aborts its active request. That is expected
      // provider teardown, not a failed release lookup worth reporting.
      if (_disposed) return null;
      rethrow;
    }
    if (response.statusCode != 200) {
      throw http.ClientException(
        'GitHub returned ${response.statusCode} for the release listing.',
        _releasesUrl,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw const FormatException('Release listing was not a JSON array.');
    }
    return latestMobileRelease(decoded);
  }
}

/// Picks the newest stable mobile release that actually carries a universal
/// APK. Exposed for tests, which drive it with recorded payloads.
MobileRelease? latestMobileRelease(List<dynamic> releases) {
  MobileRelease? best;
  for (final entry in releases) {
    if (entry is! Map<String, dynamic>) {
      continue;
    }
    // A draft's assets 404 for anyone but the publisher, and the release commit
    // reaches main before the draft is published, so a phone can see this
    // listing while the newest entry is still a draft.
    if (entry['draft'] == true || entry['prerelease'] == true) {
      continue;
    }
    final tag = entry['tag_name'];
    if (tag is! String) {
      continue;
    }
    final version = MobileVersion.tryParseTag(tag);
    if (version == null) {
      continue;
    }
    if (best != null && !version.isNewerThan(best.version)) {
      continue;
    }
    final apkUrl = _universalApkUrl(entry['assets'], version);
    if (apkUrl == null) {
      continue;
    }
    best = MobileRelease(version: version, tag: tag, apkUrl: apkUrl);
  }
  return best;
}

Uri? _universalApkUrl(dynamic assets, MobileVersion version) {
  if (assets is! List) {
    return null;
  }
  final wanted = universalApkAssetName(version);
  for (final asset in assets) {
    if (asset is! Map<String, dynamic>) {
      continue;
    }
    if (asset['name'] != wanted) {
      continue;
    }
    final url = asset['browser_download_url'];
    if (url is! String) {
      continue;
    }
    return Uri.tryParse(url);
  }
  return null;
}
