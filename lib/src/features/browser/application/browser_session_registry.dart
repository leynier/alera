import 'dart:async';

import 'package:alera/src/features/browser/application/browser_engine.dart';
import 'package:alera/src/features/browser/application/browser_page_state_reducer.dart';
import 'package:alera/src/features/browser/domain/browser_automation.dart';
import 'package:alera/src/features/browser/domain/browser_cookie.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_navigation.dart';
import 'package:alera/src/features/browser/domain/browser_page.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/infra/browser_tab_payload_codec.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/foundation.dart';

part 'browser_session_handle.dart';
part 'browser_session_commands.dart';
part 'browser_session_leases.dart';
part 'browser_session_reconciliation.dart';

enum BrowserVisibilityReason { user, automation, capture, popup }

enum BrowserObscurationReason { overlay, tabDrag }

enum BrowserLifecycleReason { command, automation, capture, overlay, popup }

enum BrowserRegistryEventKind { opened, stateChanged, closed }

final class const BrowserRegistryEvent({
  required final BrowserRegistryEventKind kind,
  required final String pageId,
  final BrowserPageState? state,
  final BrowserEngineEvent? engineEvent,
});

final class BrowserSessionRegistry({
  required BrowserEngine engine,
  BrowserTabPayloadCodec codec = const BrowserTabPayloadCodec(),
  Future<BrowserEngineCapabilities> Function()? probeCapabilities,
  Future<BrowserSearchEngine> Function()? readSearchEngine,
  DateTime Function()? now,
}) {
  this
    : _engine = engine, // ignore: prefer_initializing_formals
      _codec = codec, // ignore: prefer_initializing_formals
      _probeCapabilities = probeCapabilities ?? engine.probeCapabilities,
      _readSearchEngine = readSearchEngine ?? _defaultSearchEngine,
      _now = now ?? _defaultNow {
    _eventSubscription = _engine.events.listen(_onEngineEvent);
  }

  final BrowserEngine _engine;
  final BrowserTabPayloadCodec _codec;
  final Future<BrowserEngineCapabilities> Function() _probeCapabilities;
  final Future<BrowserSearchEngine> Function() _readSearchEngine;
  final DateTime Function() _now;
  final Map<String, _BrowserSessionEntry> _entries =
      <String, _BrowserSessionEntry>{};
  final StreamController<BrowserRegistryEvent> _registryEvents =
      StreamController<BrowserRegistryEvent>.broadcast(sync: true);
  late final StreamSubscription<BrowserEngineEvent> _eventSubscription;
  Future<BrowserEngineCapabilities>? _capabilities;
  var _disposed = false;

  static Future<BrowserSearchEngine> _defaultSearchEngine() async =>
      BrowserSearchEngine.google;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  Stream<BrowserRegistryEvent> get events => _registryEvents.stream;

  Iterable<BrowserSessionHandle> get sessions =>
      _entries.values.map((entry) => entry.handle);

  BrowserSessionHandle? handleForPageId(String pageId) =>
      _entries[pageId]?.handle;

  Future<BrowserSessionHandle> sessionFor(WorkspaceTabRecord tab) {
    return _sessionForPayload(_codec.decode(tab));
  }

  Future<BrowserSessionHandle> transientSessionFor({
    required BrowserPage page,
    required String openerPageId,
  }) {
    return _sessionForPage(
      page,
      runtimeTitle: null,
      transient: true,
      openerPageId: openerPageId,
    );
  }

  Future<BrowserSessionHandle> adoptTransientSession({
    required BrowserPage page,
    String? openerPageId,
  }) {
    return _sessionForPage(
      page,
      runtimeTitle: null,
      transient: true,
      openerPageId: openerPageId,
      adoptedTransient: true,
    );
  }

  Future<void> promoteTransientPage(String pageId) async {
    final entry = _entries[pageId];
    if (entry == null || !entry.transient) {
      throw BrowserFailure(
        code: .pageNotFound,
        message: 'Transient browser page $pageId was not found.',
      );
    }
    await entry.ready.future;
    _ensureOpen(entry);
    await _ensureOperational(entry);
    await _engine.promoteTransientPage(pageId);
    entry.transient = false;
    _emit(.opened, entry);
  }

  Future<BrowserSessionHandle> _sessionForPayload(BrowserTabPayload payload) {
    return _sessionForPage(payload.page, runtimeTitle: payload.runtimeTitle);
  }

  Future<BrowserSessionHandle> _sessionForPage(
    BrowserPage page, {
    String? runtimeTitle,
    bool transient = false,
    String? openerPageId,
    bool adoptedTransient = false,
  }) async {
    while (true) {
      _checkNotDisposed();
      final existing = _entries[page.pageId];
      if (existing == null) {
        break;
      }
      await existing.ready.future;
      if (!existing.closing && !existing.closed) {
        _validateIdentity(existing.state.value.page, page);
        return existing.handle;
      }
      final closing = existing.closeCompleter?.future;
      if (closing != null) {
        try {
          await closing;
        } on Object {
          // A failed close restores the existing entry for the next loop.
        }
      } else {
        await Future.pause(.zero);
      }
    }
    final entry = _BrowserSessionEntry(
      page: page,
      title: runtimeTitle ?? '',
      transient: transient,
      openerPageId: openerPageId,
      adoptedTransient: adoptedTransient,
    );
    entry.handle = BrowserSessionHandle._(this, entry);
    _entries[page.pageId] = entry;
    await _initialize(entry);
    return entry.handle;
  }

  Future<void> _initialize(_BrowserSessionEntry entry) async {
    try {
      final capabilities = await (_capabilities ??= _probeCapabilities());
      final availability = capabilities.meetsStableGate
          ? BrowserEngineAvailability.available
          : capabilities.engineAvailable
          ? BrowserEngineAvailability.degraded
          : BrowserEngineAvailability.unavailable;
      final reason = availability == BrowserEngineAvailability.available
          ? null
          : _capabilityReason(capabilities);
      entry.state.value = entry.state.value.copyWith(
        engineAvailability: availability,
        capabilityReason: reason,
        clearCapabilityReason: reason == null,
        updatedAt: _now(),
      );
      if (availability == BrowserEngineAvailability.available) {
        if (entry.adoptedTransient) {
          await _engine.adoptTransientPage(entry.state.value.page);
        } else {
          await _engine.createPage(
            entry.state.value.page,
            openerPageId: entry.openerPageId,
            transient: entry.transient,
          );
        }
        entry.created = true;
        _emit(.opened, entry);
      }
    } catch (error) {
      entry.state.value = entry.state.value.copyWith(
        loadPhase: .failed,
        engineAvailability: .unavailable,
        error: _failure(error),
        capabilityReason: error.toString(),
        updatedAt: _now(),
      );
    } finally {
      entry.ready.complete();
    }
  }

  Future<void> closePage(String pageId) async {
    await _closePageIf(pageId, () => true);
  }

  Future<void> _closePageIf(String pageId, bool Function() shouldClose) async {
    final entry = _entries[pageId];
    if (entry == null || !shouldClose()) {
      return;
    }
    final dependentPageIds = <String>[
      for (final candidate in _entries.values)
        if (candidate.transient && candidate.openerPageId == pageId)
          candidate.pageId,
    ];
    try {
      await Future.wait(<Future<void>>[
        for (final dependentPageId in dependentPageIds)
          _closePageIf(dependentPageId, shouldClose),
      ]);
    } finally {
      if (shouldClose()) {
        await _closeEntry(entry);
      }
    }
  }

  Future<void> _closeEntry(_BrowserSessionEntry entry) async {
    entry.closing = true;
    final completion = entry.closeCompleter ??= Completer<void>();
    if (entry.lifecycleCount == 0) {
      await _finishClose(entry);
    }
    await completion.future;
  }

  Future<void> _finishClose(_BrowserSessionEntry entry) async {
    if (entry.closed) {
      return;
    }
    entry.closed = true;
    try {
      await entry.ready.future;
      await entry.visibilityTail.catchError((Object _) {});
      if (entry.created && !entry.nativeClosed) {
        await _engine.closePage(entry.pageId);
      }
    } catch (error, stackTrace) {
      entry.closed = false;
      entry.closing = false;
      final completion = entry.closeCompleter;
      entry.closeCompleter = null;
      completion?.completeError(error, stackTrace);
      return;
    }
    _entries.remove(entry.pageId);
    _emit(.closed, entry);
    entry.state.dispose();
    entry.closeCompleter?.complete();
  }

  void _onEngineEvent(BrowserEngineEvent event) {
    final entry = _entries[event.pageId];
    if (entry == null || entry.closed) {
      return;
    }
    if (event is BrowserPageClosed) {
      entry.nativeClosed = true;
      unawaited(closePage(event.pageId));
      return;
    }
    entry.state.value = reduceBrowserPageEvent(entry.state.value, event);
    _emit(.stateChanged, entry, engineEvent: event);
  }

  Future<void> _ensureOperational(_BrowserSessionEntry entry) async {
    if (!entry.created ||
        entry.state.value.engineAvailability !=
            BrowserEngineAvailability.available) {
      throw BrowserFailure(
        code: .engineUnavailable,
        message:
            entry.state.value.capabilityReason ??
            'The browser engine is unavailable.',
        recoverable: true,
      );
    }
  }

  void _emit(
    BrowserRegistryEventKind kind,
    _BrowserSessionEntry entry, {
    BrowserEngineEvent? engineEvent,
  }) {
    if (!_registryEvents.isClosed) {
      _registryEvents.add(
        BrowserRegistryEvent(
          kind: kind,
          pageId: entry.pageId,
          state: kind == BrowserRegistryEventKind.closed
              ? null
              : entry.state.value,
          engineEvent: engineEvent,
        ),
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _eventSubscription.cancel();
    for (final entry in _entries.values.toList(growable: false)) {
      await _closeEntry(entry);
    }
    await _registryEvents.close();
  }

  void _ensureOpen(_BrowserSessionEntry entry) {
    _checkNotDisposed();
    if (entry.closing || entry.closed) {
      throw BrowserFailure(
        code: .pageNotFound,
        message: 'Browser page ${entry.pageId} is closing.',
        recoverable: true,
      );
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('Browser session registry is disposed.');
    }
  }
}

final class _BrowserSessionEntry({
  required BrowserPage page,
  required String title,
  required var bool transient,
  required final String? openerPageId,
  required final bool adoptedTransient,
}) {
  this
    : state = ValueNotifier<BrowserPageState>(
        BrowserPageState.initial(page).copyWith(title: title),
      );

  final ValueNotifier<BrowserPageState> state;

  final Completer<void> ready = Completer<void>();
  late final BrowserSessionHandle handle;
  Future<void> visibilityTail = Future<void>.value();
  Future<void> obscurationTail = Future<void>.value();
  Completer<void>? closeCompleter;
  int visibilityCount = 0;
  int obscurationCount = 0;
  int lifecycleCount = 0;
  bool commandInFlight = false;
  bool created = false;
  bool nativeClosed = false;
  bool closing = false;
  bool closed = false;

  String get pageId => state.value.pageId;
}

String _capabilityReason(BrowserEngineCapabilities capabilities) {
  final missingSources = capabilities.platformRequiredNativeCookieImportSources
      .difference(capabilities.nativeCookieImportSources);
  final reasons = <String>[
    ...capabilities.limitations.map(browserCapabilityLimitationMessage),
    if (!capabilities.meetsBrowserTabGate)
      'The browser engine does not meet the stable tab capability gate.',
    if (!capabilities.meetsCookieImportGate)
      'The browser engine does not meet the cookie import gate.',
    if (missingSources.isNotEmpty)
      'Missing cookie import sources: ${missingSources.join(', ')}.',
  ];
  return reasons.isEmpty
      ? 'The browser engine does not meet the stable capability gate.'
      : reasons.join(' ');
}

BrowserFailure _failure(Object error) {
  if (error is BrowserFailure) {
    return error;
  }
  return BrowserFailure(
    code: .engineUnavailable,
    message: error.toString(),
    recoverable: true,
  );
}

void _validateIdentity(BrowserPage existing, BrowserPage requested) {
  if (existing.workspaceId != requested.workspaceId ||
      existing.profileId != requested.profileId) {
    throw BrowserFailure(
      code: .invalidPayload,
      message: 'Browser page ${requested.pageId} changed identity.',
    );
  }
}
