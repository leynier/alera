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

part 'browser_tab_annotation.dart';

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

  void _updateAnnotationState(VoidCallback callback) => setState(callback);

  @override
  void initState() {
    super.initState();
    _addressController.text = widget.tab.browserUrl ?? '';
    _session = _loadSessionFor(widget.tab);
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
      _session = _loadSessionFor(widget.tab);
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
              browserStateShowsNativeSurface(state) &&
                  routeIsCurrent &&
                  TickerMode.valuesOf(context).enabled,
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
    final lease = handle.tryAcquireVisibility(BrowserVisibilityReason.user);
    if (lease == null) {
      _visibilityAcquisitions.remove(identity);
      return;
    }
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
}
