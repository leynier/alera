part of 'browser_session_registry.dart';

final class BrowserSessionHandle {
  const BrowserSessionHandle._(this._registry, this._entry);

  final BrowserSessionRegistry _registry;
  final _BrowserSessionEntry _entry;

  BrowserPageState get state => _entry.state.value;

  ValueListenable<BrowserPageState> get stateListenable => _entry.state;

  BrowserSurfaceToken get surfaceToken => BrowserSurfaceToken(_entry.pageId);

  Future<BrowserNavigationTarget> loadUrl(
    String input, {
    BrowserOperationGuard? guard,
  }) => _registry._loadUrl(_entry, input, guard: guard);

  Future<void> back({BrowserOperationGuard? guard}) =>
      _command(() => _registry._engine.back(pageId), guard: guard);

  Future<void> forward({BrowserOperationGuard? guard}) =>
      _command(() => _registry._engine.forward(pageId), guard: guard);

  Future<void> reload({BrowserOperationGuard? guard}) =>
      _command(() => _registry._engine.reload(pageId), guard: guard);

  Future<void> stop({BrowserOperationGuard? guard}) =>
      _command(() => _registry._engine.stop(pageId), guard: guard);

  Future<Object?> evaluateJavaScript(
    String expression, {
    BrowserOperationGuard? guard,
  }) => _registry._runCommand<Object?>(
    _entry,
    BrowserLifecycleReason.automation,
    () => _registry._engine.evaluateJavaScript(pageId, expression),
    guard: guard,
  );

  Future<BrowserAutomationSnapshot> snapshot({
    bool interactiveOnly = false,
    int maxNodes = 500,
    BrowserOperationGuard? guard,
  }) => _registry._runCommand<BrowserAutomationSnapshot>(
    _entry,
    BrowserLifecycleReason.automation,
    () => _registry._engine.snapshot(
      pageId,
      interactiveOnly: interactiveOnly,
      maxNodes: maxNodes,
    ),
    guard: guard,
  );

  Future<void> performAction(
    BrowserAutomationAction action, {
    BrowserOperationGuard? guard,
  }) => _registry._runCommand<void>(
    _entry,
    BrowserLifecycleReason.automation,
    () => _registry._engine.performAction(pageId, action),
    guard: guard,
  );

  Future<List<BrowserCookie>> getCookies({
    Uri? url,
    BrowserOperationGuard? guard,
  }) => _registry._runCommand<List<BrowserCookie>>(
    _entry,
    BrowserLifecycleReason.automation,
    () => _registry._engine.getCookies(pageId, url: url),
    guard: guard,
  );

  Future<void> deleteCookies({
    String? name,
    Uri? url,
    String? domain,
    String? path,
    BrowserOperationGuard? guard,
  }) => _registry._runCommand<void>(
    _entry,
    BrowserLifecycleReason.automation,
    () => _registry._engine.deleteCookies(
      pageId,
      name: name,
      url: url,
      domain: domain,
      path: path,
    ),
    guard: guard,
  );

  Future<BrowserArtifactResult> captureScreenshot({
    required String destinationPath,
    required DateTime expiresAt,
    bool fullPage = false,
    BrowserOperationGuard? guard,
  }) => _registry._runCommand<BrowserArtifactResult>(
    _entry,
    BrowserLifecycleReason.capture,
    () => _registry._engine.captureScreenshot(
      pageId,
      destinationPath: destinationPath,
      expiresAt: expiresAt,
      fullPage: fullPage,
    ),
    guard: guard,
  );

  Future<BrowserArtifactResult> printToPdf({
    required String destinationPath,
    required DateTime expiresAt,
    BrowserOperationGuard? guard,
  }) => _registry._runCommand<BrowserArtifactResult>(
    _entry,
    BrowserLifecycleReason.capture,
    () => _registry._engine.printToPdf(
      pageId,
      destinationPath: destinationPath,
      expiresAt: expiresAt,
    ),
    guard: guard,
  );

  BrowserVisibilityLease acquireVisibility(BrowserVisibilityReason reason) =>
      _registry._acquireVisibility(_entry, reason);

  BrowserVisibilityLease? tryAcquireVisibility(
    BrowserVisibilityReason reason,
  ) => _registry._tryAcquireVisibility(_entry, reason);

  BrowserObscurationLease acquireObscuration(BrowserObscurationReason reason) =>
      _registry._acquireObscuration(_entry, reason);

  BrowserLifecycleLease acquireLifecycle(BrowserLifecycleReason reason) =>
      _registry._acquireLifecycleForHandle(_entry, reason);

  Future<T> withFlutterOverlay<T>(Future<T> Function() operation) =>
      _registry._withFlutterOverlay(_entry, operation);

  Future<void> close() => _registry.closePage(pageId);

  String get pageId => _entry.pageId;

  bool get isTransient => _entry.transient;

  Future<void> _command(
    Future<void> Function() operation, {
    BrowserOperationGuard? guard,
  }) => _registry._runCommand<void>(
    _entry,
    BrowserLifecycleReason.command,
    operation,
    guard: guard,
  );
}

final class BrowserVisibilityLease {
  BrowserVisibilityLease._({
    required this.reason,
    required this.ready,
    required Future<void> Function() release,
  }) : _release = release; // ignore: prefer_initializing_formals

  final BrowserVisibilityReason reason;
  final Future<void> ready;
  final Future<void> Function() _release;
  var _disposed = false;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _release();
  }
}

final class BrowserObscurationLease {
  BrowserObscurationLease._({
    required this.reason,
    required this.ready,
    required Future<void> Function() release,
  }) : _release = release; // ignore: prefer_initializing_formals

  final BrowserObscurationReason reason;
  final Future<void> ready;
  final Future<void> Function() _release;
  var _disposed = false;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _release();
  }
}

final class BrowserLifecycleLease {
  BrowserLifecycleLease._({
    required this.reason,
    required Future<void> Function() release,
  }) : _release = release; // ignore: prefer_initializing_formals

  final BrowserLifecycleReason reason;
  final Future<void> Function() _release;
  var _disposed = false;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _release();
  }
}
