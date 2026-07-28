// ignore_for_file: prefer_initializing_formals

import 'package:alera/src/features/browser/application/browser_closed_tabs_service.dart';
import 'package:alera/src/features/browser/domain/browser_navigation.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera_browser/alera_browser.dart';
import 'package:uuid/uuid.dart';

class WorkspaceBrowserTabService {
  WorkspaceBrowserTabService({
    required WorkbenchRepository repository,
    BrowserClosedTabsService? closedTabsService,
    Uuid uuid = const Uuid(),
    DateTime Function()? now,
  }) : _repository = repository,
       _closedTabsService = closedTabsService,
       _uuid = uuid,
       _now = now ?? _defaultNow;

  final WorkbenchRepository _repository;
  final BrowserClosedTabsService? _closedTabsService;
  final Uuid _uuid;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  Future<void> closeTab(String tabId) async {
    final service = _closedTabsService;
    if (service == null) {
      await _repository.removeWorkspaceTab(tabId);
      return;
    }
    if (!await service.close(tabId)) {
      throw StateError('Browser tab could not be closed: $tabId');
    }
  }

  Future<WorkspaceTabRecord> createTab(
    String workspaceId, {
    String? pageId,
    String profileId = 'default',
    String? initialUrl,
  }) async {
    final normalizedPageId = pageId?.trim();
    if (pageId != null &&
        (normalizedPageId == null || normalizedPageId.isEmpty)) {
      throw StateError('Browser page id must not be empty');
    }
    final trimmedProfileId = profileId.trim();
    if (trimmedProfileId.isEmpty) {
      throw StateError('Browser profile id must not be empty');
    }
    final trimmedUrl = isPersistableBrowserUrl(initialUrl)
        ? initialUrl!.trim()
        : null;
    final now = _now();
    final tab = WorkspaceTabRecord(
      id: normalizedPageId ?? _uuid.v4(),
      workspaceId: workspaceId,
      kind: WorkspaceTabKind.browser,
      title: 'New Tab',
      createdAt: now,
      updatedAt: now,
      payload: <String, Object?>{
        workspaceTabBrowserProfileIdPayloadKey: trimmedProfileId,
        if (trimmedUrl != null && trimmedUrl.isNotEmpty)
          workspaceTabBrowserUrlPayloadKey: trimmedUrl,
      },
    );
    return _repository.upsertWorkspaceTab(tab);
  }

  Future<WorkspaceTabRecord> updateState({
    required String tabId,
    required String profileId,
    String? url,
    String? runtimeTitle,
  }) async {
    final tab = await _repository.findWorkspaceTabById(tabId);
    if (tab == null || tab.kind != WorkspaceTabKind.browser) {
      throw StateError('Browser tab not found: $tabId');
    }
    final urlMayPersist = url != null && isPersistableBrowserUrl(url);
    final safeRuntimeTitle = !urlMayPersist || runtimeTitle == null
        ? null
        : normalizeAleraBrowserTitle(runtimeTitle);
    final nextPayload = <String, Object?>{
      ...tab.payload,
      workspaceTabBrowserProfileIdPayloadKey: profileId,
    };
    _setOptionalPayloadString(
      nextPayload,
      workspaceTabBrowserUrlPayloadKey,
      isPersistableBrowserUrl(url) ? url : null,
    );
    _setOptionalPayloadString(
      nextPayload,
      workspaceTabBrowserRuntimeTitlePayloadKey,
      safeRuntimeTitle,
    );
    final normalizedRuntimeTitle = safeRuntimeTitle?.trim();
    final next = tab.copyWith(
      title: tab.hasManualTitle
          ? tab.title
          : !urlMayPersist
          ? tab.title
          : normalizedRuntimeTitle == null || normalizedRuntimeTitle.isEmpty
          ? 'New Tab'
          : normalizedRuntimeTitle,
      updatedAt: _now(),
      payload: nextPayload,
    );
    return _repository.upsertWorkspaceTab(next);
  }

  static void _setOptionalPayloadString(
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
}
