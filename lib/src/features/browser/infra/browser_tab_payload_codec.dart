import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_navigation.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_browser/alera_browser.dart';

final class BrowserTabPayload {
  const BrowserTabPayload({required this.page, this.runtimeTitle});

  final BrowserPage page;
  final String? runtimeTitle;
}

final class BrowserTabPayloadCodec {
  const BrowserTabPayloadCodec();

  BrowserTabPayload decode(WorkspaceTabRecord record) {
    if (record.kind != WorkspaceTabKind.browser) {
      throw const BrowserFailure(
        code: BrowserErrorCode.invalidPayload,
        message: 'The workspace tab is not a browser tab.',
      );
    }
    final rawUrl = record.browserUrl;
    final initialUrl = rawUrl == null ? Uri.parse('about:blank') : _uri(rawUrl);
    return BrowserTabPayload(
      page: BrowserPage(
        pageId: record.id,
        workspaceId: record.workspaceId,
        profileId: record.browserProfileId,
        initialUrl: initialUrl,
        createdAt: record.createdAt.toUtc(),
      ),
      runtimeTitle:
          rawUrl == null ||
              !isPersistableBrowserUrl(rawUrl) ||
              record.browserRuntimeTitle == null
          ? null
          : normalizeAleraBrowserTitle(record.browserRuntimeTitle!),
    );
  }

  Map<String, Object?> encodePayload({
    required Map<String, Object?> existing,
    required String profileId,
    Uri? url,
    String? runtimeTitle,
  }) {
    final normalizedProfileId = profileId.trim();
    if (normalizedProfileId.isEmpty) {
      throw const BrowserFailure(
        code: BrowserErrorCode.invalidPayload,
        message: 'The browser profile id is empty.',
      );
    }
    final payload = <String, Object?>{
      ...existing,
      workspaceTabBrowserProfileIdPayloadKey: normalizedProfileId,
    };
    final encodedUrl = url != null && isPersistableBrowserUrl(url.toString())
        ? url.toString()
        : null;
    _setOptionalString(payload, workspaceTabBrowserUrlPayloadKey, encodedUrl);
    _setOptionalString(
      payload,
      workspaceTabBrowserRuntimeTitlePayloadKey,
      url == null || encodedUrl == null
          ? null
          : runtimeTitle == null
          ? null
          : normalizeAleraBrowserTitle(runtimeTitle),
    );
    return Map<String, Object?>.unmodifiable(payload);
  }

  Uri _uri(String value) {
    final uri = Uri.tryParse(value);
    final isBlank = uri?.toString() == 'about:blank';
    final isSafeWebUrl =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        isPersistableBrowserUrl(uri.toString());
    if (!isBlank && !isSafeWebUrl) {
      throw const BrowserFailure(
        code: BrowserErrorCode.invalidPayload,
        message: 'The saved browser address is invalid or sensitive.',
        recoverable: true,
      );
    }
    return uri!;
  }
}

void _setOptionalString(
  Map<String, Object?> payload,
  String key,
  String? value,
) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    payload.remove(key);
  } else {
    payload[key] = normalized;
  }
}
