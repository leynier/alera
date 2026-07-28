final class BrowserCookie {
  const BrowserCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.secure = false,
    this.httpOnly = false,
    this.sameSite = BrowserCookieSameSite.unspecified,
    this.expiresAt,
  });

  factory BrowserCookie.fromJson(Map<String, Object?> json) {
    if (json['name'] is! String ||
        json['value'] is! String ||
        json['domain'] is! String) {
      throw const FormatException('Browser Cookie Payload Is Invalid.');
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

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool httpOnly;
  final BrowserCookieSameSite sameSite;
  final DateTime? expiresAt;

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
