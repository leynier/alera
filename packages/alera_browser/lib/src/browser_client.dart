import 'dart:math';

import 'package:flutter/widgets.dart';

import 'browser_callbacks.dart';
import 'browser_capabilities.dart';
import 'browser_cookie_import.dart';
import 'browser_events.dart';
import 'browser_models.dart';
import 'browser_platform.dart';
import 'native_browser_platform.dart';

/// Stable public entry point for browser tabs and headless automation leases.
final class AleraBrowserClient({
  AleraBrowserPlatform? platform,
  AleraBrowserCallbacks callbacks = const AleraBrowserCallbacks(),
  DateTime Function()? now,
}) {
  this
    : _platform =
          platform ??
          NativeAleraBrowserPlatform(callbacks: callbacks, now: now),
      _now = now ?? DateTime.now;

  static const Duration _gestureLifetime = Duration(seconds: 15);

  final AleraBrowserPlatform _platform;
  final DateTime Function() _now;
  final Random _random = .secure();
  final Map<String, Set<String>> _attachmentLeases = <String, Set<String>>{};
  final Map<String, Future<void>> _attachmentTransitions =
      <String, Future<void>>{};
  final Set<String> _gestureTokens = <String>{};
  var _disposed = false;

  Stream<AleraBrowserEvent> get events => _platform.events;

  Future<AleraBrowserCapabilities> probeCapabilities() =>
      _platform.probeCapabilities();

  Future<AleraBrowserProfile> createProfile(
    AleraBrowserProfileOptions options,
  ) => _platform.createProfile(options);

  Future<List<AleraBrowserProfile>> listProfiles() => _platform.listProfiles();

  Future<void> deleteProfile(String profileId) =>
      _platform.deleteProfile(profileId);

  Future<AleraBrowserPage> createPage(AleraBrowserPageOptions options) =>
      _platform.createPage(options);

  Future<AleraBrowserPage> adoptTransientPage(
    String pageId, {
    required String profileId,
  }) => _platform.adoptTransientPage(pageId, profileId: profileId);

  Future<AleraBrowserPage> promoteTransientPage(String pageId) =>
      _platform.promoteTransientPage(pageId);

  /// Attaches on the first lease and is otherwise idempotent per [leaseId].
  Future<void> attachPage(String pageId, {String leaseId = 'default'}) =>
      _enqueueAttachmentTransition(pageId, () async {
        final leases = _attachmentLeases[pageId];
        if (leases?.contains(leaseId) ?? false) {
          return;
        }
        if (leases != null && leases.isNotEmpty) {
          leases.add(leaseId);
          return;
        }
        await _platform.attachPage(pageId);
        _attachmentLeases[pageId] = <String>{leaseId};
      });

  /// Detaches only after the last independent visibility lease is released.
  Future<void> detachPage(String pageId, {String leaseId = 'default'}) =>
      _enqueueAttachmentTransition(pageId, () async {
        final leases = _attachmentLeases[pageId];
        if (leases == null || !leases.contains(leaseId)) {
          return;
        }
        if (leases.length > 1) {
          leases.remove(leaseId);
          return;
        }
        await _platform.detachPage(pageId);
        _attachmentLeases.remove(pageId);
      });

  Future<void> closePage(String pageId) =>
      _enqueueAttachmentTransition(pageId, () async {
        await _platform.closePage(pageId);
        _attachmentLeases.remove(pageId);
      });

  Future<void> _enqueueAttachmentTransition(
    String pageId,
    Future<void> Function() operation,
  ) {
    if (_disposed) {
      return Future<void>.error(
        StateError('The browser client has been disposed.'),
      );
    }
    final previous = _attachmentTransitions[pageId];
    final ready = previous == null
        ? Future<void>.value()
        : _ignoreAttachmentFailure(previous);
    late final Future<void> transition;
    transition = ready.then((_) => operation()).whenComplete(() {
      if (identical(_attachmentTransitions[pageId], transition)) {
        _attachmentTransitions.remove(pageId);
      }
    });
    _attachmentTransitions[pageId] = transition;
    return transition;
  }

  Future<void> _ignoreAttachmentFailure(Future<void> transition) async {
    try {
      await transition;
    } on Object {
      // A later lease transition must still be allowed to repair native state.
    }
  }

  /// Temporarily hides a native overlay while Flutter owns the visual layer.
  Future<void> setPageObscured(String pageId, bool obscured) =>
      _platform.setPageObscured(pageId, obscured);

  Widget buildPageView(String pageId, {Key? key}) =>
      _platform.buildPageView(pageId, key: key);

  Future<void> loadUrl(
    String pageId,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
  }) => _platform.loadUrl(pageId, url, headers: headers);

  Future<Uri?> currentUrl(String pageId) => _platform.currentUrl(pageId);

  Future<String?> title(String pageId) => _platform.title(pageId);

  Future<bool> canGoBack(String pageId) => _platform.canGoBack(pageId);

  Future<bool> canGoForward(String pageId) => _platform.canGoForward(pageId);

  Future<void> goBack(String pageId) => _platform.goBack(pageId);

  Future<void> goForward(String pageId) => _platform.goForward(pageId);

  Future<void> reload(String pageId) => _platform.reload(pageId);

  Future<void> stop(String pageId) => _platform.stop(pageId);

  Future<Object?> evaluateJavaScript(String pageId, String script) =>
      _platform.evaluateJavaScript(pageId, script);

  Future<List<AleraBrowserCookie>> getCookies(String profileId, Uri url) =>
      _platform.getCookies(profileId, url);

  Future<void> setCookie(String profileId, AleraBrowserCookie cookie) =>
      _platform.setCookie(profileId, cookie);

  Future<int> deleteCookies(
    String profileId,
    AleraBrowserCookieFilter filter,
  ) => _platform.deleteCookies(profileId, filter);

  Future<AleraBrowserSnapshot> snapshot(
    String pageId, {
    AleraBrowserSnapshotOptions options = const AleraBrowserSnapshotOptions(),
  }) => _platform.snapshot(pageId, options);

  Future<void> performAction(String pageId, AleraBrowserAction action) =>
      _platform.performAction(pageId, action);

  Future<void> waitFor(
    String pageId,
    AleraBrowserWaitCondition condition, {
    Duration timeout = const Duration(seconds: 30),
  }) => _platform.waitFor(pageId, condition, timeout: timeout);

  Future<AleraBrowserArtifact> captureScreenshotToFile(
    String pageId, {
    required String destinationPath,
    AleraBrowserScreenshotOptions options =
        const AleraBrowserScreenshotOptions(),
  }) => _platform.captureScreenshotToFile(pageId, destinationPath, options);

  Future<AleraBrowserArtifact> printToPdfFile(
    String pageId, {
    required String destinationPath,
    AleraBrowserPdfOptions options = const AleraBrowserPdfOptions(),
  }) => _platform.printToPdfFile(pageId, destinationPath, options);

  /// Must be called synchronously from an explicit UI gesture handler.
  AleraBrowserUserGestureToken beginCookieImportGesture() {
    final now = _now();
    final id = List<int>.generate(
      4,
      (_) => _random.nextInt(1 << 32),
    ).map((value) => value.toRadixString(16).padLeft(8, '0')).join();
    _gestureTokens.add(id);
    return AleraBrowserUserGestureToken.internal(id, now);
  }

  Future<List<AleraBrowserCookieImportSourceStatus>> probeCookieImportSources(
    AleraBrowserUserGestureToken gestureToken,
  ) {
    _consumeGesture(gestureToken);
    return _platform.probeCookieImportSources();
  }

  Future<AleraBrowserCookieImportResult> importCookies(
    AleraBrowserCookieImportRequest request,
  ) {
    _consumeGesture(request.gestureToken);
    return _platform.importCookies(request);
  }

  void _consumeGesture(AleraBrowserUserGestureToken token) {
    final fresh = _now().difference(token.issuedAt) <= _gestureLifetime;
    if (!fresh || !_gestureTokens.remove(token.id)) {
      throw StateError(
        'Cookie import requires a fresh, unused explicit UI gesture.',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await Future.wait<void>(<Future<void>>[
      for (final transition in _attachmentTransitions.values)
        _ignoreAttachmentFailure(transition),
    ]);
    _attachmentTransitions.clear();
    _attachmentLeases.clear();
    _gestureTokens.clear();
    await _platform.dispose();
  }
}
