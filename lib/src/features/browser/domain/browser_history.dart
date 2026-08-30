final class const BrowserHistoryEntry({
  required final String id,
  required final String profileId,
  required final Uri url,
  required final String title,
  required final DateTime lastVisitedAt,
  final int visitCount = 1,
  final String? workspaceId,
  final String? pageId,
}) {
  factory fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final profileId = json['profileId'];
    final url = Uri.tryParse(json['url'] as String? ?? '');
    final lastVisitedAt = DateTime.tryParse(
      (json['visitedAt'] ?? json['lastVisitedAt']) as String? ?? '',
    );
    if (id is! String ||
        profileId is! String ||
        url == null ||
        lastVisitedAt == null) {
      throw const FormatException('Browser history entry is invalid.');
    }
    return BrowserHistoryEntry(
      id: id,
      profileId: profileId,
      url: url,
      title: json['title'] as String? ?? '',
      lastVisitedAt: lastVisitedAt.toUtc(),
      visitCount: (json['visitCount'] as num?)?.toInt() ?? 1,
      workspaceId: json['workspaceId'] as String?,
      pageId: (json['tabId'] ?? json['pageId']) as String?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'profileId': profileId,
    'url': url.toString(),
    'title': title,
    'visitedAt': lastVisitedAt.toUtc().toIso8601String(),
    'visitCount': visitCount,
    if (workspaceId != null) 'workspaceId': workspaceId,
    if (pageId != null) 'tabId': pageId,
  };
}

final class const BrowserClosedTab({
  required final String id,
  required final String workspaceId,
  required final String profileId,
  required final Uri url,
  required final String title,
  required final DateTime closedAt,
  final Map<String, Object?> payload = const <String, Object?>{},
}) {
  factory fromJson(Map<String, Object?> json) {
    final url = Uri.tryParse(json['url'] as String? ?? '');
    final closedAt = DateTime.tryParse(json['closedAt'] as String? ?? '');
    if ((json['id'] ?? json['pageId']) is! String ||
        json['workspaceId'] is! String ||
        json['profileId'] is! String ||
        url == null ||
        closedAt == null) {
      throw const FormatException('Closed browser tab is invalid.');
    }
    return BrowserClosedTab(
      id: (json['id'] ?? json['pageId'])! as String,
      workspaceId: json['workspaceId']! as String,
      profileId: json['profileId']! as String,
      url: url,
      title: json['title'] as String? ?? '',
      closedAt: closedAt.toUtc(),
      payload: _historyMap(json['payload']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'workspaceId': workspaceId,
    'profileId': profileId,
    'url': url.toString(),
    'title': title,
    'payload': payload,
    'closedAt': closedAt.toUtc().toIso8601String(),
  };
}

Map<String, Object?> _historyMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiableOf(Map<String, Object?>.from(value));
}
