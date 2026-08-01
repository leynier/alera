final class BrowserHistoryEntry {
  const BrowserHistoryEntry({
    required this.id,
    required this.profileId,
    required this.url,
    required this.title,
    required this.lastVisitedAt,
    this.visitCount = 1,
    this.workspaceId,
    this.pageId,
  });

  factory BrowserHistoryEntry.fromJson(Map<String, Object?> json) {
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

  final String id;
  final String profileId;
  final Uri url;
  final String title;
  final DateTime lastVisitedAt;
  final int visitCount;
  final String? workspaceId;
  final String? pageId;

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

final class BrowserClosedTab {
  const BrowserClosedTab({
    required this.id,
    required this.workspaceId,
    required this.profileId,
    required this.url,
    required this.title,
    required this.closedAt,
    this.payload = const <String, Object?>{},
  });

  factory BrowserClosedTab.fromJson(Map<String, Object?> json) {
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

  final String id;
  final String workspaceId;
  final String profileId;
  final Uri url;
  final String title;
  final DateTime closedAt;
  final Map<String, Object?> payload;

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
  return Map<String, Object?>.unmodifiable(Map<String, Object?>.from(value));
}
