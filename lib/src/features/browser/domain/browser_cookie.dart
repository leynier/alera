final class const BrowserCookie({
  required final String name,
  required final String value,
  required final String domain,
  final String path = '/',
  final bool secure = false,
  final bool httpOnly = false,
  final BrowserCookieSameSite sameSite = BrowserCookieSameSite.unspecified,
  final DateTime? expiresAt,
}) {
  factory fromJson(Map<String, Object?> json) {
    if (json['name'] is! String ||
        json['value'] is! String ||
        json['domain'] is! String) {
      throw const FormatException('Browser cookie payload is invalid.');
    }
    return BrowserCookie(
      name: json['name']! as String,
      value: json['value']! as String,
      domain: json['domain']! as String,
      path: json['path'] as String? ?? '/',
      secure: json['secure'] == true,
      httpOnly: json['httpOnly'] == true,
      sameSite: BrowserCookieSameSite.values.firstWhere(
        (value) => value.name == json['sameSite'],
        orElse: () => BrowserCookieSameSite.unspecified,
      ),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toUtc(),
    );
  }

  Map<String, Object?> toJson({bool includeValue = true}) => <String, Object?>{
    'name': name,
    if (includeValue) 'value': value,
    'domain': domain,
    'path': path,
    'secure': secure,
    'httpOnly': httpOnly,
    'sameSite': sameSite.name,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
  };
}

enum BrowserCookieSameSite { unspecified, none, lax, strict }
