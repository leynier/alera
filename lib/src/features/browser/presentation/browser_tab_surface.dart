import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/browser/application/browser_profile_session_switch.dart';
import 'package:alera/src/features/browser/application/browser_providers.dart';
import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/domain/browser_annotation.dart';
import 'package:alera/src/features/codex_chat/application/codex_composer_draft_store.dart';
import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/browser/domain/browser_profile.dart';
import 'package:alera/src/features/browser/presentation/browser_downloads_dialog.dart';
import 'package:alera/src/features/browser/presentation/browser_page_body.dart';
import 'package:alera/src/features/browser/presentation/browser_profile_picker_dialog.dart';
import 'package:alera/src/features/browser/presentation/browser_security_dialog.dart';
import 'package:alera/src/features/browser/presentation/browser_tab_drag_placeholder.dart';
import 'package:alera/src/features/browser/presentation/browser_toolbar.dart';
import 'package:alera/src/features/browser/presentation/browser_annotation_overlay.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:alera/src/shared/infra/uri/uri_providers.dart';
import 'package:alera_browser/alera_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class BrowserTabSurface extends ConsumerStatefulWidget {
  const BrowserTabSurface({
    super.key,
    required this.tab,
    this.autofocus = false,
    this.pageObscured = false,
  });

  final WorkspaceTabRecord tab;
  final bool autofocus;
  final bool pageObscured;

  @override
  ConsumerState<BrowserTabSurface> createState() => _BrowserTabSurfaceState();
}

class _BrowserTabSurfaceState extends ConsumerState<BrowserTabSurface> {
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode(debugLabel: 'BrowserAddress');
  Future<BrowserSessionHandle>? _session;
  List<BrowserProfile> _profileValues = const <BrowserProfile>[];
  BrowserVisibilityLease? _visibility;
  BrowserObscurationLease? _obscuration;
  Object? _sessionIdentity;
  bool _wantsNativeVisibility = false;
  bool _wantsNativeObscuration = false;
  bool _annotationMode = false;
  BrowserAnnotationInputMode _annotationInputMode =
      BrowserAnnotationInputMode.element;
  BrowserAnnotationCapture? _annotationCapture;
  List<BrowserAnnotationElement> _annotationElements =
      const <BrowserAnnotationElement>[];
  final Set<Object> _visibilityAcquisitions = <Object>{};
  final Set<Object> _obscurationAcquisitions = <Object>{};

  @override
  void initState() {
    super.initState();
    _addressController.text = widget.tab.browserUrl ?? '';
    _session = _loadSession();
    unawaited(_loadProfiles());
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _addressController.text.isEmpty) {
          _addressFocusNode.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(BrowserTabSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab.id != widget.tab.id ||
        oldWidget.tab.workspaceId != widget.tab.workspaceId ||
        oldWidget.tab.browserProfileId != widget.tab.browserProfileId) {
      unawaited(_releasePresentation());
      _session = _loadSession();
      unawaited(_loadProfiles());
    }
  }

  @override
  void dispose() {
    unawaited(_releasePresentation());
    _addressController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  Future<BrowserSessionHandle> _loadSession() async {
    return _loadSessionFor(widget.tab);
  }

  Future<BrowserSessionHandle> _loadSessionFor(
    WorkspaceTabRecord tab, {
    bool reconcileIdentity = false,
  }) async {
    final identity = Object();
    _sessionIdentity = identity;
    final registry = ref.read(browserSessionRegistryProvider);
    final handle = await (reconcileIdentity
        ? registry.reconcilePersistentSession(tab)
        : registry.sessionFor(tab));
    if (!identical(_sessionIdentity, identity)) {
      throw StateError('The browser session was replaced.');
    }
    return handle;
  }

  Future<List<BrowserProfile>> _loadProfiles() async {
    late final List<BrowserProfile> values;
    try {
      values = await ref.read(browserProfileServiceProvider).list();
    } on Object {
      values = <BrowserProfile>[
        BrowserProfile(
          id: defaultBrowserProfileId,
          label: 'Default',
          kind: BrowserProfileKind.defaultProfile,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
      ];
    }
    if (mounted) {
      setState(() => _profileValues = values);
    }
    return values;
  }

  Future<void> _releasePresentation() async {
    _wantsNativeVisibility = false;
    _wantsNativeObscuration = false;
    _sessionIdentity = null;
    final visibility = _visibility;
    final obscuration = _obscuration;
    _visibility = null;
    _obscuration = null;
    await Future.wait(<Future<void>>[
      if (visibility != null) visibility.dispose(),
      if (obscuration != null) obscuration.dispose(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return FutureBuilder<BrowserSessionHandle>(
      future: session,
      builder: (context, snapshot) {
        final handle = snapshot.data;
        if (handle == null) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Browser session unavailable: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        }
        return ValueListenableBuilder<BrowserPageState>(
          valueListenable: handle.stateListenable,
          builder: (context, state, _) {
            _syncAddress(state.url);
            final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
            _syncNativeVisibility(
              handle,
              browserStateShowsNativeSurface(state) && routeIsCurrent,
            );
            _syncNativeObscuration(
              handle,
              widget.pageObscured || _annotationMode,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                BrowserToolbar(
                  state: state,
                  addressController: _addressController,
                  addressFocusNode: _addressFocusNode,
                  profileLabel: _profileLabel(state.profileId),
                  onBack: state.canGoBack
                      ? () => _runCommand(handle.back)
                      : null,
                  onForward: state.canGoForward
                      ? () => _runCommand(handle.forward)
                      : null,
                  onStopOrReload: () => _runCommand(
                    state.isLoading ? handle.stop : handle.reload,
                  ),
                  onSubmitAddress: (input) {
                    _addressFocusNode.unfocus();
                    _runCommand(() async {
                      await handle.loadUrl(input);
                    });
                  },
                  onShowSecurity: () => _showSecurity(handle, state),
                  onSelectProfile: () => _showProfiles(handle, state),
                  onShowDownloads: () => _showDownloads(handle, state),
                  onAnnotate: browserStateShowsNativeSurface(state)
                      ? () => _beginAnnotation(handle, state)
                      : null,
                  onOpenDevTools: null,
                  onOpenExternally: canOpenBrowserUrlExternally(state.url)
                      ? () => _openExternally(state.url)
                      : null,
                ),
                const Divider(height: AleraTokens.dividerExtent),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      BrowserPageBody(
                        state: state,
                        surface: _BrowserNativePageSurface(
                          pageId: handle.pageId,
                        ),
                        onRetry: () => _runCommand(handle.reload),
                        onOpenExternally: canOpenBrowserUrlExternally(state.url)
                            ? () => _openExternally(state.url)
                            : null,
                      ),
                      if (widget.pageObscured)
                        const BrowserTabDragPlaceholder(),
                      if (_annotationMode && _annotationCapture != null)
                        BrowserAnnotationOverlay(
                          capture: _annotationCapture!,
                          mode: _annotationInputMode,
                          onModeChanged: (mode) =>
                              setState(() => _annotationInputMode = mode),
                          onElementSelected: (rect) =>
                              _selectAnnotationElement(handle, rect),
                          onRegionSelected: (rect) => _addAnnotationComment(
                            handle,
                            BrowserAnnotationKind.region,
                            rect,
                          ),
                          onDelete: (comment) => setState(() {
                            final current = _annotationCapture!;
                            final comments = current.comments.toList()
                              ..removeWhere((item) => item.id == comment.id);
                            _annotationCapture = current.copyWith(
                              comments:
                                  List<BrowserAnnotationComment>.unmodifiable(
                                    comments,
                                  ),
                            );
                          }),
                          onCancel: _cancelAnnotation,
                          onDone: () => _finishAnnotation(handle),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _syncNativeVisibility(
    BrowserSessionHandle handle,
    bool shouldBeVisible,
  ) {
    _wantsNativeVisibility = shouldBeVisible;
    if (!shouldBeVisible) {
      final visibility = _visibility;
      _visibility = null;
      if (visibility != null) {
        unawaited(visibility.dispose());
      }
      return;
    }
    if (_visibility != null) {
      return;
    }
    final identity = _sessionIdentity;
    if (identity == null || !_visibilityAcquisitions.add(identity)) {
      return;
    }
    final lease = handle.acquireVisibility(BrowserVisibilityReason.user);
    unawaited(() async {
      try {
        await lease.ready;
        if (!mounted ||
            !_wantsNativeVisibility ||
            !identical(_sessionIdentity, identity)) {
          await lease.dispose();
        } else {
          _visibility = lease;
        }
      } catch (_) {
        await lease.dispose();
      } finally {
        _visibilityAcquisitions.remove(identity);
      }
    }());
  }

  void _syncNativeObscuration(
    BrowserSessionHandle handle,
    bool shouldBeObscured,
  ) {
    _wantsNativeObscuration = shouldBeObscured;
    if (!shouldBeObscured) {
      final obscuration = _obscuration;
      _obscuration = null;
      if (obscuration != null) {
        unawaited(obscuration.dispose());
      }
      return;
    }
    if (_obscuration != null) {
      return;
    }
    final identity = _sessionIdentity;
    if (identity == null || !_obscurationAcquisitions.add(identity)) {
      return;
    }
    final lease = handle.acquireObscuration(
      _annotationMode
          ? BrowserObscurationReason.overlay
          : BrowserObscurationReason.tabDrag,
    );
    unawaited(() async {
      try {
        await lease.ready;
        if (!mounted ||
            !_wantsNativeObscuration ||
            !identical(_sessionIdentity, identity)) {
          await lease.dispose();
        } else {
          _obscuration = lease;
        }
      } catch (_) {
        await lease.dispose();
      } finally {
        _obscurationAcquisitions.remove(identity);
      }
    }());
  }

  void _syncAddress(Uri url) {
    if (_addressFocusNode.hasFocus) {
      return;
    }
    final value = url.toString() == 'about:blank' ? '' : url.toString();
    if (_addressController.text != value) {
      _addressController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  String _profileLabel(String profileId) {
    for (final profile in _profileValues) {
      if (profile.id == profileId) {
        return profile.label;
      }
    }
    return profileId == defaultBrowserProfileId ? 'Default' : 'Profile';
  }

  Future<void> _showProfiles(
    BrowserSessionHandle handle,
    BrowserPageState state,
  ) async {
    final profiles = await _loadProfiles();
    if (!mounted) {
      return;
    }
    final selected = await handle.withFlutterOverlay(
      () => showDialog<String>(
        context: context,
        builder: (_) => BrowserProfilePickerDialog(
          profiles: profiles,
          currentProfileId: state.profileId,
          onManageProfiles: () => unawaited(openSettingsDialog(context)),
        ),
      ),
    );
    if (selected == null || selected == state.profileId || !mounted) {
      return;
    }
    await _runCommand(() async {
      WorkspaceTabRecord? updatedTab;
      try {
        await switchBrowserSessionProfile(
          registry: ref.read(browserSessionRegistryProvider),
          currentSession: handle,
          currentTab: widget.tab,
          persist: () async {
            final persistedTab = await ref
                .read(workbenchControllerProvider.notifier)
                .updateBrowserTabState(
                  tabId: widget.tab.id,
                  profileId: selected,
                  url: state.url.toString(),
                  runtimeTitle: state.title,
                );
            updatedTab = persistedTab;
            return persistedTab;
          },
        );
      } finally {
        await _showSession(
          updatedTab ?? widget.tab,
          reconcileIdentity: updatedTab != null,
        );
      }
    });
  }

  Future<void> _showSession(
    WorkspaceTabRecord tab, {
    bool reconcileIdentity = false,
  }) async {
    await _releasePresentation();
    if (!mounted) {
      return;
    }
    _addressController.text = tab.browserUrl ?? '';
    setState(
      () =>
          _session = _loadSessionFor(tab, reconcileIdentity: reconcileIdentity),
    );
  }

  Future<void> _showSecurity(
    BrowserSessionHandle handle,
    BrowserPageState state,
  ) {
    return handle.withFlutterOverlay(
      () => showDialog<void>(
        context: context,
        builder: (_) => BrowserSecurityDialog(security: state.security),
      ),
    );
  }

  Future<void> _showDownloads(
    BrowserSessionHandle handle,
    BrowserPageState state,
  ) {
    return handle.withFlutterOverlay(
      () => showDialog<void>(
        context: context,
        builder: (_) => BrowserDownloadsDialog(
          downloads: state.downloads,
          onOpen: (download) {
            final path = download.savePath;
            if (path != null) {
              unawaited(_openExternally(Uri.file(path)));
            }
          },
          onReveal: (download) {
            final path = download.savePath;
            if (path != null) {
              unawaited(_openExternally(Uri.directory(p.dirname(path))));
            }
          },
        ),
      ),
    );
  }

  Future<void> _openExternally(Uri uri) {
    return _runCommand(() => ref.read(externalUriLauncherProvider).open(uri));
  }

  Future<void> _beginAnnotation(
    BrowserSessionHandle handle,
    BrowserPageState state,
  ) async {
    if (_annotationMode) return;
    try {
      final raw = await handle.evaluateJavaScript(
        _browserAnnotationSnapshotScript,
      );
      final snapshot = _decodeAnnotationSnapshot(raw);
      final directory = await getTemporaryDirectory();
      final annotationDirectory = Directory(
        p.join(directory.path, 'alera-browser-annotations'),
      );
      await annotationDirectory.create(recursive: true);
      final imagePath = p.join(
        annotationDirectory.path,
        '${const Uuid().v4()}.png',
      );
      final artifact = await handle.captureScreenshot(
        destinationPath: imagePath,
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 24)),
      );
      if (!mounted) return;
      setState(() {
        _annotationElements = snapshot.elements;
        _annotationCapture = BrowserAnnotationCapture(
          imagePath: artifact.path,
          url: state.url,
          title: state.title,
          viewportWidth: snapshot.viewportWidth,
          viewportHeight: snapshot.viewportHeight,
          comments: const <BrowserAnnotationComment>[],
          capturedAt: DateTime.now().toUtc(),
        );
        _annotationInputMode = BrowserAnnotationInputMode.element;
        _annotationMode = true;
      });
    } catch (error) {
      if (mounted) {
        AleraToast.show(
          context,
          message: 'Could not start annotation mode: $error',
          tone: AleraToastTone.error,
        );
      }
    }
  }

  Future<void> _selectAnnotationElement(
    BrowserSessionHandle handle,
    Rect point,
  ) async {
    final candidates =
        _annotationElements.where((element) {
          final anchor = element.anchor;
          return point.left >= anchor.x &&
              point.left <= anchor.x + anchor.width &&
              point.top >= anchor.y &&
              point.top <= anchor.y + anchor.height;
        }).toList()..sort(
          (left, right) => (left.anchor.width * left.anchor.height).compareTo(
            right.anchor.width * right.anchor.height,
          ),
        );
    final anchor = candidates.isEmpty
        ? BrowserAnnotationAnchor(
            x: point.left,
            y: point.top,
            width: 0,
            height: 0,
          )
        : candidates.first.anchor;
    await _addAnnotationComment(
      handle,
      BrowserAnnotationKind.element,
      Rect.fromLTWH(anchor.x, anchor.y, anchor.width, anchor.height),
      anchor: anchor,
    );
  }

  Future<void> _addAnnotationComment(
    BrowserSessionHandle handle,
    BrowserAnnotationKind kind,
    Rect rect, {
    BrowserAnnotationAnchor? anchor,
  }) async {
    final text = await handle.withFlutterOverlay(
      () => _showAnnotationCommentDialog(kind),
    );
    if (!mounted || text == null || text.trim().isEmpty) return;
    final capture = _annotationCapture;
    if (capture == null) return;
    final nextAnchor =
        anchor ??
        BrowserAnnotationAnchor(
          x: rect.left,
          y: rect.top,
          width: rect.width,
          height: rect.height,
        );
    final next = <BrowserAnnotationComment>[
      ...capture.comments,
      BrowserAnnotationComment(
        id: const Uuid().v4(),
        kind: kind,
        anchor: nextAnchor,
        text: _limitAnnotationText(text),
      ),
    ];
    setState(
      () => _annotationCapture = capture.copyWith(
        comments: List<BrowserAnnotationComment>.unmodifiable(next),
      ),
    );
  }

  Future<String?> _showAnnotationCommentDialog(BrowserAnnotationKind kind) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          kind == BrowserAnnotationKind.element
              ? 'Comment On Element'
              : 'Comment On Region',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          maxLength: 4000,
          decoration: const InputDecoration(
            hintText: 'Describe the issue and the result you want.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save Comment'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _finishAnnotation(BrowserSessionHandle handle) async {
    final capture = _annotationCapture;
    if (capture == null || capture.comments.isEmpty) {
      if (mounted) {
        AleraToast.show(context, message: 'Add at least one comment first.');
      }
      return;
    }
    final workbench = ref.read(workbenchControllerProvider);
    final codexTabs = workbench
        .tabsFor(widget.tab.workspaceId)
        .where((tab) => tab.kind == WorkspaceTabKind.codex)
        .toList(growable: false);
    WorkspaceTabRecord? target = codexTabs.isEmpty ? null : codexTabs.first;
    if (target == null) {
      Workspace? workspace;
      for (final candidate in workbench.workspacesByProject.values.expand(
        (items) => items,
      )) {
        if (candidate.id == widget.tab.workspaceId) {
          workspace = candidate;
          break;
        }
      }
      if (workspace != null) {
        target = await ref
            .read(workbenchControllerProvider.notifier)
            .createCodexTab(workspace);
      }
    }
    if (target == null) {
      if (mounted) {
        AleraToast.show(
          context,
          message: 'Open a Codex tab before adding browser comments.',
          tone: AleraToastTone.error,
        );
      }
      return;
    }
    final attachment = CodexInputAttachment(
      id: const Uuid().v4(),
      path: capture.imagePath,
      isImage: true,
      mimeType: 'image/png',
      displayName: capture.displayName,
      annotationContext: capture.contextText,
      annotationUrl: capture.url.toString(),
      annotationTitle: capture.title,
      annotationCount: capture.comments.length,
    );
    ref
        .read(codexComposerDraftStoreProvider)
        .addBrowserAnnotation(target.id, attachment);
    ref
        .read(workbenchControllerProvider.notifier)
        .setActiveTab(workspaceId: widget.tab.workspaceId, tabId: target.id);
    if (mounted) {
      setState(() {
        _annotationMode = false;
        _annotationCapture = null;
        _annotationElements = const <BrowserAnnotationElement>[];
      });
      AleraToast.show(context, message: 'Browser comments added to Codex.');
    }
  }

  void _cancelAnnotation() {
    if (!mounted) return;
    setState(() {
      _annotationMode = false;
      _annotationCapture = null;
      _annotationElements = const <BrowserAnnotationElement>[];
    });
  }

  Future<void> _runCommand(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        AleraToast.show(
          context,
          message: error.toString(),
          tone: AleraToastTone.error,
        );
      }
    }
  }
}

final class _BrowserAnnotationSnapshot {
  const _BrowserAnnotationSnapshot({
    required this.viewportWidth,
    required this.viewportHeight,
    required this.elements,
  });

  final int viewportWidth;
  final int viewportHeight;
  final List<BrowserAnnotationElement> elements;
}

_BrowserAnnotationSnapshot _decodeAnnotationSnapshot(Object? raw) {
  Object? value = raw;
  for (var index = 0; index < 2 && value is String; index++) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      break;
    }
  }
  if (value is! Map) {
    throw const FormatException('Browser annotation snapshot is invalid.');
  }
  final viewportWidth = (value['viewportWidth'] as num?)?.toInt() ?? 1;
  final viewportHeight = (value['viewportHeight'] as num?)?.toInt() ?? 1;
  final elements = <BrowserAnnotationElement>[];
  final rawElements = value['elements'];
  if (rawElements is List) {
    for (final rawElement in rawElements) {
      if (rawElement is! Map) continue;
      final x = (rawElement['x'] as num?)?.toDouble();
      final y = (rawElement['y'] as num?)?.toDouble();
      final width = (rawElement['width'] as num?)?.toDouble();
      final height = (rawElement['height'] as num?)?.toDouble();
      if (x == null || y == null || width == null || height == null) continue;
      elements.add(
        BrowserAnnotationElement(
          anchor: BrowserAnnotationAnchor(
            x: x.clamp(0.0, 1.0).toDouble(),
            y: y.clamp(0.0, 1.0).toDouble(),
            width: width.clamp(0.0, 1.0).toDouble(),
            height: height.clamp(0.0, 1.0).toDouble(),
            role: rawElement['role'] as String?,
            name: rawElement['name'] as String?,
            tag: rawElement['tag'] as String?,
          ),
        ),
      );
    }
  }
  return _BrowserAnnotationSnapshot(
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    elements: List<BrowserAnnotationElement>.unmodifiable(elements),
  );
}

const _browserAnnotationSnapshotScript = r'''
(() => {
  const viewportWidth = Math.max(1, window.innerWidth || 1);
  const viewportHeight = Math.max(1, window.innerHeight || 1);
  const elements = [];
  const interactive = new Set(['A','BUTTON','INPUT','SELECT','TEXTAREA','SUMMARY','OPTION']);
  const semantic = new Set(['H1','H2','H3','H4','H5','H6','P','LABEL','LI','TH','TD','PRE','CODE']);
  const visible = (element) => {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return style.display !== 'none' && style.visibility !== 'hidden' &&
      rect.width >= 4 && rect.height >= 4 && rect.bottom >= 0 && rect.right >= 0 &&
      rect.left <= viewportWidth && rect.top <= viewportHeight;
  };
  const role = (element) => element.getAttribute('role') ||
    ({A:'link',BUTTON:'button',INPUT:'textbox',SELECT:'combobox',TEXTAREA:'textbox'}[element.tagName] || 'generic');
  const name = (element) => (element.getAttribute('aria-label') || element.getAttribute('alt') ||
    element.getAttribute('title') || element.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 240);
  for (const element of document.querySelectorAll('*')) {
    if (elements.length >= 400 || !visible(element)) continue;
    const rect = element.getBoundingClientRect();
    if (!interactive.has(element.tagName) && !semantic.has(element.tagName) &&
        role(element) === 'generic' && !element.hasAttribute('tabindex')) continue;
    elements.push({
      x: Math.max(0, rect.left / viewportWidth),
      y: Math.max(0, rect.top / viewportHeight),
      width: Math.min(1, rect.width / viewportWidth),
      height: Math.min(1, rect.height / viewportHeight),
      role: role(element), name: name(element), tag: element.tagName.toLowerCase(),
    });
  }
  return JSON.stringify({viewportWidth, viewportHeight, elements});
})()
''';

class _BrowserNativePageSurface extends ConsumerWidget {
  const _BrowserNativePageSurface({required this.pageId});

  final String pageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AleraBrowserView(
      client: ref.watch(aleraBrowserClientProvider),
      pageId: pageId,
    );
  }
}

bool canOpenBrowserUrlExternally(Uri uri) {
  return uri.host.isNotEmpty && (uri.scheme == 'http' || uri.scheme == 'https');
}

String _limitAnnotationText(String value) {
  final trimmed = value.trim();
  return trimmed.length <= 4000 ? trimmed : trimmed.substring(0, 4000);
}
