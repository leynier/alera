import 'package:alera/src/features/browser/domain/browser_profile.dart';

final class const BrowserPage({
  required final String pageId,
  required final String workspaceId,
  required final String profileId,
  required final Uri initialUrl,
  required final DateTime createdAt,
}) {
  factory fromJson(Map<String, Object?> json) {
    final pageId = json['pageId'];
    final workspaceId = json['workspaceId'];
    final profileId = json['profileId'];
    final initialUrl = Uri.tryParse(json['initialUrl'] as String? ?? '');
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (pageId is! String ||
        workspaceId is! String ||
        profileId is! String ||
        initialUrl == null ||
        createdAt == null) {
      throw const FormatException('Browser page payload is invalid.');
    }
    return BrowserPage(
      pageId: pageId,
      workspaceId: workspaceId,
      profileId: profileId,
      initialUrl: initialUrl,
      createdAt: createdAt.toUtc(),
    );
  }

  BrowserPage copyWith({String? profileId, Uri? initialUrl}) {
    return BrowserPage(
      pageId: pageId,
      workspaceId: workspaceId,
      profileId: profileId ?? this.profileId,
      initialUrl: initialUrl ?? this.initialUrl,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'pageId': pageId,
    'workspaceId': workspaceId,
    'profileId': profileId,
    'initialUrl': initialUrl.toString(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static BrowserPage blank({
    required String pageId,
    required String workspaceId,
    String profileId = defaultBrowserProfileId,
    DateTime? createdAt,
  }) {
    return BrowserPage(
      pageId: pageId,
      workspaceId: workspaceId,
      profileId: profileId,
      initialUrl: Uri.parse('about:blank'),
      createdAt: createdAt?.toUtc() ?? DateTime.now().toUtc(),
    );
  }
}
