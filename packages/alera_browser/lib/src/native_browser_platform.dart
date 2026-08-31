import 'dart:async';

import 'package:flutter/widgets.dart';

import 'browser_callbacks.dart';
import 'browser_capabilities.dart';
import 'browser_cookie_import.dart';
import 'browser_errors.dart';
import 'browser_events.dart';
import 'browser_models.dart';
import 'browser_platform.dart';
import 'browser_title.dart';
import 'native_browser_automation.dart';
import 'native_browser_channel.dart';
import 'native_browser_data_store.dart';
import 'native_browser_serialization.dart';
import 'native_browser_surface.dart';

part 'native_browser_platform_events.dart';

final class NativeAleraBrowserPlatform({
  required final AleraBrowserCallbacks callbacks,
  AleraBrowserNativeChannel channel = const AleraBrowserNativeChannel(),
  DateTime Function()? now,
}) implements AleraBrowserPlatform {
  this
    : _channel = channel,
      _now = now ?? DateTime.now,
      _dataStore = AleraNativeBrowserDataStore(channel) {
    _automation = AleraNativeBrowserAutomation(
      evaluate: evaluateJavaScript,
      generation: (pageId) => _page(pageId).generation,
      now: _now,
      namespace: 'alera-${identityHashCode(this).toRadixString(16)}',
    );
    _eventSubscription = _channel.events.listen(
      _handleNativeEvent,
      onError: _events.addError,
    );
  }

  final AleraBrowserNativeChannel _channel;
  final DateTime Function() _now;
  final AleraNativeBrowserDataStore _dataStore;
  final StreamController<AleraBrowserEvent> _events =
      StreamController<AleraBrowserEvent>.broadcast();
  final Map<String, _NativePage> _pages = <String, _NativePage>{};
  late final AleraNativeBrowserAutomation _automation;
  late final StreamSubscription<Map<Object?, Object?>> _eventSubscription;
  AleraBrowserCapabilities? _capabilities;

  @override
  Stream<AleraBrowserEvent> get events => _events.stream;

  @override
  Future<AleraBrowserCapabilities> probeCapabilities() async =>
      _capabilities ??= decodeNativeBrowserCapabilities(
        await _channel.invokeMap('probe'),
      );

  @override
  Future<AleraBrowserProfile> createProfile(
    AleraBrowserProfileOptions options,
  ) async {
    final value = await _channel.invokeMap('profile.create', <String, Object?>{
      'id': options.id,
      'storage': options.storage.name,
    });
    return decodeNativeBrowserProfile(value);
  }

  @override
  Future<List<AleraBrowserProfile>> listProfiles() async {
    final values = await _channel.invokeList('profile.list');
    return values
        .whereType<Map<Object?, Object?>>()
        .map(decodeNativeBrowserProfile)
        .toList(growable: false);
  }

  @override
  Future<void> deleteProfile(String profileId) => _channel.invokeVoid(
    'profile.delete',
    <String, Object?>{'profileId': profileId},
  );

  @override
  Future<AleraBrowserPage> createPage(AleraBrowserPageOptions options) async {
    final value = await _channel.invokeMap('page.create', <String, Object?>{
      'id': options.id,
      'profileId': options.profileId,
      'initialUrl': options.initialUrl?.toString(),
      'userAgent': options.userAgent,
      'openerPageId': options.openerPageId,
      'transient': options.transient,
    });
    final id = value['id'] as String? ?? options.id;
    if (id == null || id.isEmpty) {
      throw const AleraBrowserNativeError(
        'invalid_page',
        'The native engine did not return a page id.',
      );
    }
    if (_pages.containsKey(id)) {
      throw AleraBrowserStateError(
        'duplicate_page',
        'Browser page "$id" already exists.',
      );
    }
    final page = AleraBrowserPage(
      id: id,
      profileId: options.profileId,
      url: options.initialUrl,
      title: switch (value['title']) {
        final String title => normalizeAleraBrowserTitle(title),
        _ => null,
      },
      isAttached: false,
      openerPageId: options.openerPageId,
      transient: options.transient,
    );
    _pages[id] = _NativePage(page);
    return page;
  }

  @override
  Future<void> attachPage(String pageId) async {
    final page = _page(pageId);
    if (page.model.isAttached) {
      return;
    }
    if (page.wasAttached) {
      _invalidatePage(pageId);
    }
    await _channel.invokeVoid('page.attach', <String, Object?>{
      'pageId': pageId,
    });
    page.wasAttached = true;
    page.model = _copyPage(page.model, isAttached: true);
  }

  @override
  Future<AleraBrowserPage> adoptTransientPage(
    String pageId, {
    required String profileId,
  }) async {
    final page = _page(pageId);
    if (!page.model.transient || page.model.profileId != profileId) {
      throw const AleraBrowserStateError(
        'invalid_transient_page',
        'The transient popup does not match the requested profile.',
      );
    }
    await _channel.invokeVoid('page.adoptTransient', <String, Object?>{
      'pageId': pageId,
      'profileId': profileId,
    });
    return page.model;
  }

  @override
  Future<AleraBrowserPage> promoteTransientPage(String pageId) async {
    final page = _page(pageId);
    if (!page.model.transient) {
      return page.model;
    }
    await _channel.invokeVoid('page.promoteTransient', <String, Object?>{
      'pageId': pageId,
    });
    page.model = AleraBrowserPage(
      id: page.model.id,
      profileId: page.model.profileId,
      url: page.model.url,
      title: page.model.title,
      isAttached: page.model.isAttached,
      openerPageId: page.model.openerPageId,
      transient: false,
    );
    return page.model;
  }

  @override
  Future<void> detachPage(String pageId) async {
    final page = _page(pageId);
    if (!page.model.isAttached) {
      return;
    }
    await _channel.invokeVoid('page.detach', <String, Object?>{
      'pageId': pageId,
    });
    page.model = _copyPage(page.model, isAttached: false);
  }

  @override
  Future<void> setPageObscured(String pageId, bool obscured) =>
      _channel.invokeVoid('page.setObscured', <String, Object?>{
        'pageId': pageId,
        'obscured': obscured,
      });

  @override
  Future<void> closePage(String pageId) async {
    final page = _pages[pageId];
    if (page == null) {
      return;
    }
    await _channel.invokeVoid('page.close', <String, Object?>{
      'pageId': pageId,
    });
    _automation.invalidate(pageId);
    _pages.remove(pageId);
  }

  @override
  Widget buildPageView(String pageId, {Key? key}) {
    _page(pageId);
    return AleraNativeBrowserSurface(
      key: key,
      onBoundsChanged: (bounds, scale) => _setBounds(pageId, bounds, scale),
    );
  }

  Future<void> _setBounds(String pageId, Rect bounds, double scale) =>
      _channel.invokeVoid('page.setBounds', <String, Object?>{
        'pageId': pageId,
        'x': bounds.left,
        'y': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
        'scale': scale,
      });

  @override
  Future<void> loadUrl(
    String pageId,
    Uri url, {
    Map<String, String> headers = const <String, String>{},
  }) => _channel.invokeVoid('page.loadUrl', <String, Object?>{
    'pageId': pageId,
    'url': url.toString(),
    'headers': headers,
  });

  @override
  Future<Uri?> currentUrl(String pageId) async {
    final value = await _channel.invoke<String>('page.currentUrl', {
      'pageId': pageId,
    });
    return value == null ? null : Uri.tryParse(value);
  }

  @override
  Future<String?> title(String pageId) async {
    final title = await _channel.invoke<String>('page.title', {
      'pageId': pageId,
    });
    return title == null ? null : normalizeAleraBrowserTitle(title);
  }

  @override
  Future<bool> canGoBack(String pageId) async =>
      await _channel.invoke<bool>('page.canGoBack', {'pageId': pageId}) ??
      false;

  @override
  Future<bool> canGoForward(String pageId) async =>
      await _channel.invoke<bool>('page.canGoForward', {'pageId': pageId}) ??
      false;

  @override
  Future<void> goBack(String pageId) => _pageCommand('page.goBack', pageId);

  @override
  Future<void> goForward(String pageId) =>
      _pageCommand('page.goForward', pageId);

  @override
  Future<void> reload(String pageId) {
    _invalidatePage(pageId);
    return _pageCommand('page.reload', pageId);
  }

  @override
  Future<void> stop(String pageId) => _pageCommand('page.stop', pageId);

  Future<void> _pageCommand(String method, String pageId) {
    _page(pageId);
    return _channel.invokeVoid(method, <String, Object?>{'pageId': pageId});
  }

  @override
  Future<Object?> evaluateJavaScript(String pageId, String script) {
    _page(pageId);
    return _channel.invoke<Object>('page.evaluateJavaScript', {
      'pageId': pageId,
      'script': script,
    });
  }

  @override
  Future<List<AleraBrowserCookie>> getCookies(String profileId, Uri url) =>
      _dataStore.getCookies(profileId, url);

  @override
  Future<void> setCookie(String profileId, AleraBrowserCookie cookie) =>
      _dataStore.setCookie(profileId, cookie);

  @override
  Future<int> deleteCookies(
    String profileId,
    AleraBrowserCookieFilter filter,
  ) => _dataStore.deleteCookies(profileId, filter);

  @override
  Future<AleraBrowserSnapshot> snapshot(
    String pageId,
    AleraBrowserSnapshotOptions options,
  ) => _automation.snapshot(pageId, options);

  @override
  Future<void> performAction(String pageId, AleraBrowserAction action) {
    if (action.kind == AleraBrowserActionKind.upload) {
      return _channel.invokeVoid('page.upload', <String, Object?>{
        'pageId': pageId,
        'elementRef': action.elementRef,
        'filePaths': action.filePaths,
      });
    }
    return _automation.performAction(pageId, action);
  }

  @override
  Future<void> waitFor(
    String pageId,
    AleraBrowserWaitCondition condition, {
    required Duration timeout,
  }) => _automation.waitFor(pageId, condition, timeout: timeout);

  @override
  Future<AleraBrowserArtifact> captureScreenshotToFile(
    String pageId,
    String destinationPath,
    AleraBrowserScreenshotOptions options,
  ) async => decodeNativeBrowserArtifact(
    await _channel.invokeMap('capture.screenshot', <String, Object?>{
      'pageId': pageId,
      'destinationPath': destinationPath,
      'fullPage': options.fullPage,
      'scale': options.scale,
    }),
  );

  @override
  Future<AleraBrowserArtifact> printToPdfFile(
    String pageId,
    String destinationPath,
    AleraBrowserPdfOptions options,
  ) async => decodeNativeBrowserArtifact(
    await _channel.invokeMap('capture.pdf', <String, Object?>{
      'pageId': pageId,
      'destinationPath': destinationPath,
      'landscape': options.landscape,
      'printBackground': options.printBackground,
    }),
  );

  @override
  Future<List<AleraBrowserCookieImportSourceStatus>>
  probeCookieImportSources() => _dataStore.probeCookieImportSources();

  @override
  Future<AleraBrowserCookieImportResult> importCookies(
    AleraBrowserCookieImportRequest request,
  ) => _dataStore.importCookies(request);

  _NativePage _page(String pageId) {
    final page = _pages[pageId];
    if (page == null) {
      throw AleraBrowserStateError(
        'page_not_found',
        'Browser page "$pageId" does not exist.',
      );
    }
    return page;
  }

  AleraBrowserPage _copyPage(
    AleraBrowserPage page, {
    Uri? url,
    String? title,
    bool? isAttached,
  }) => AleraBrowserPage(
    id: page.id,
    profileId: page.profileId,
    url: url ?? page.url,
    title: title ?? page.title,
    isAttached: isAttached ?? page.isAttached,
    openerPageId: page.openerPageId,
    transient: page.transient,
  );

  @override
  Future<void> dispose() async {
    final pageIds = _pages.keys.toList(growable: false);
    for (final pageId in pageIds) {
      await closePage(pageId);
    }
    await _eventSubscription.cancel();
    await _events.close();
  }
}

final class _NativePage(var AleraBrowserPage model) {
  int generation = 0;
  bool wasAttached = false;
}
