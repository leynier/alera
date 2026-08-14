part of 'browser_tab_surface.dart';

extension _BrowserAnnotationActions on _BrowserTabSurfaceState {
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
      _updateAnnotationState(() {
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
    _updateAnnotationState(
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
      _updateAnnotationState(() {
        _annotationMode = false;
        _annotationCapture = null;
        _annotationElements = const <BrowserAnnotationElement>[];
      });
      AleraToast.show(context, message: 'Browser comments added to Codex.');
    }
  }

  void _cancelAnnotation() {
    if (!mounted) return;
    _updateAnnotationState(() {
      _annotationMode = false;
      _annotationCapture = null;
      _annotationElements = const <BrowserAnnotationElement>[];
    });
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

String _limitAnnotationText(String value) {
  final trimmed = value.trim();
  return trimmed.length <= 4000 ? trimmed : trimmed.substring(0, 4000);
}

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
