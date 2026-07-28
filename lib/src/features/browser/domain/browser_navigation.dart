import 'package:alera/src/features/browser/domain/browser_error.dart';

const int maxBrowserAddressLength = 4096;

enum BrowserSearchEngine { google, duckDuckGo, bing, kagi }

enum BrowserNavigationKind { blank, url, search }

final class BrowserNavigationTarget {
  const BrowserNavigationTarget({
    required this.url,
    required this.kind,
    required this.originalInput,
  });

  final Uri url;
  final BrowserNavigationKind kind;
  final String originalInput;
}

final class BrowserNavigationPolicy {
  const BrowserNavigationPolicy({
    this.searchEngine = BrowserSearchEngine.google,
  });

  final BrowserSearchEngine searchEngine;

  BrowserNavigationTarget resolve(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      return BrowserNavigationTarget(
        url: Uri.parse('about:blank'),
        kind: BrowserNavigationKind.blank,
        originalInput: input,
      );
    }
    if (normalized.length > maxBrowserAddressLength) {
      throw const BrowserFailure(
        code: BrowserErrorCode.invalidUrl,
        message: 'The Browser Address Is Too Long.',
        recoverable: true,
      );
    }
    if (_looksLikeFilePath(normalized)) {
      throw const BrowserFailure(
        code: BrowserErrorCode.navigationBlocked,
        message: 'Local File Paths Cannot Be Opened In Browser Tabs.',
        recoverable: true,
      );
    }
    if (_looksLikeHost(normalized)) {
      final scheme = _isLocalHostInput(normalized) ? 'http' : 'https';
      final uri = Uri.tryParse('$scheme://$normalized');
      if (uri == null || uri.host.isEmpty) {
        throw _invalidAddress();
      }
      return BrowserNavigationTarget(
        url: uri,
        kind: BrowserNavigationKind.url,
        originalInput: input,
      );
    }
    final explicitScheme = _schemePattern.firstMatch(normalized)?.group(1);
    if (explicitScheme != null) {
      final uri = Uri.tryParse(normalized);
      if (uri == null) {
        throw _invalidAddress();
      }
      final scheme = explicitScheme.toLowerCase();
      if (!_allowedSchemes.contains(scheme) ||
          (scheme == 'about' && uri.toString() != 'about:blank')) {
        throw BrowserFailure(
          code: BrowserErrorCode.navigationBlocked,
          message: 'The "$scheme" Browser Address Is Not Allowed.',
          recoverable: true,
        );
      }
      if (scheme != 'about' && (uri.host.isEmpty || uri.userInfo.isNotEmpty)) {
        throw _invalidAddress();
      }
      return BrowserNavigationTarget(
        url: uri,
        kind: scheme == 'about'
            ? BrowserNavigationKind.blank
            : BrowserNavigationKind.url,
        originalInput: input,
      );
    }
    return BrowserNavigationTarget(
      url: _searchUri(normalized),
      kind: BrowserNavigationKind.search,
      originalInput: input,
    );
  }

  Uri _searchUri(String query) {
    final (host, path, parameter) = switch (searchEngine) {
      BrowserSearchEngine.google => ('www.google.com', '/search', 'q'),
      BrowserSearchEngine.duckDuckGo => ('duckduckgo.com', '/', 'q'),
      BrowserSearchEngine.bing => ('www.bing.com', '/search', 'q'),
      BrowserSearchEngine.kagi => ('kagi.com', '/search', 'q'),
    };
    return Uri.https(host, path, <String, String>{parameter: query});
  }
}

final class BrowserHistorySensitivityFilter {
  const BrowserHistorySensitivityFilter();

  bool shouldPersist(Uri url) {
    if (url.scheme != 'http' && url.scheme != 'https') {
      return false;
    }
    if (url.host.isEmpty || url.userInfo.isNotEmpty) {
      return false;
    }
    if (url.queryParametersAll.keys.any(_isSensitiveKey)) {
      return false;
    }
    final decodedPath = Uri.decodeComponent(url.path).toLowerCase();
    if (_sensitivePathFragments.any(decodedPath.contains)) {
      return false;
    }
    if (_containsSensitiveFragment(Uri.decodeComponent(url.fragment))) {
      return false;
    }
    return true;
  }
}

/// Returns whether [rawUrl] is safe to save in tab state or browser history.
bool isPersistableBrowserUrl(String? rawUrl) {
  final normalized = rawUrl?.trim();
  if (normalized == null || normalized.isEmpty) {
    return false;
  }
  final url = Uri.tryParse(normalized);
  return url != null &&
      const BrowserHistorySensitivityFilter().shouldPersist(url);
}

const Set<String> _allowedSchemes = <String>{'about', 'http', 'https'};

const List<String> _sensitivePathFragments = <String>[
  '/oauth/callback',
  '/oauth2/callback',
  '/auth/callback',
  '/signin-oidc',
  '/saml/acs',
  '/magic-link',
  '/reset-password',
  '/password-reset',
];

final RegExp _schemePattern = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):');
final RegExp _windowsPathPattern = RegExp(r'^[a-zA-Z]:[\\/]');
final RegExp _hostPattern = RegExp(
  r'^(?:localhost|(?:\d{1,3}\.){3}\d{1,3}|\[[0-9a-fA-F:]+\]|'
  r'(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,})(?::\d+)?(?:[/?#].*)?$',
);
final RegExp _localHostPattern = RegExp(
  r'^(?:localhost|127(?:\.\d{1,3}){3}|0\.0\.0\.0|\[::1\])'
  r'(?::\d+)?(?:[/?#].*)?$',
  caseSensitive: false,
);
bool _looksLikeFilePath(String value) =>
    value.startsWith('/') || _windowsPathPattern.hasMatch(value);

bool _looksLikeHost(String value) => _hostPattern.hasMatch(value);

bool _isLocalHostInput(String value) => _localHostPattern.hasMatch(value);

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return _sensitiveQueryKeys.contains(normalized) ||
      normalized.endsWith('token') ||
      normalized.endsWith('secret') ||
      normalized.endsWith('password') ||
      normalized.endsWith('signature');
}

const Set<String> _sensitiveQueryKeys = <String>{
  'accesstoken',
  'apikey',
  'assertion',
  'auth',
  'authorization',
  'code',
  'credential',
  'idtoken',
  'jwt',
  'key',
  'oauth',
  'oauthtoken',
  'passwd',
  'password',
  'refreshtoken',
  'samlrequest',
  'samlresponse',
  'secret',
  'session',
  'sessionid',
  'sig',
  'signature',
  'state',
  'ticket',
  'token',
};

bool _containsSensitiveFragment(String value) {
  final normalized = value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  return _sensitiveQueryKeys.any(normalized.contains);
}

BrowserFailure _invalidAddress() => const BrowserFailure(
  code: BrowserErrorCode.invalidUrl,
  message: 'The Browser Address Is Invalid.',
  recoverable: true,
);
