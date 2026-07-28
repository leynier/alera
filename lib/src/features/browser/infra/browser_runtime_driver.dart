import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:alera/src/features/browser/application/browser_engine.dart';
import 'package:alera/src/features/browser/application/browser_session_registry.dart';
import 'package:alera/src/features/browser/domain/browser_automation.dart';
import 'package:alera/src/features/browser/domain/browser_engine_models.dart';
import 'package:alera/src/features/browser/domain/browser_engine_event.dart';
import 'package:alera/src/features/browser/domain/browser_error.dart';
import 'package:alera/src/features/browser/domain/browser_navigation.dart';
import 'package:alera/src/features/browser/domain/browser_page_state.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_payload.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera_browser/alera_browser.dart';
import 'package:flutter/foundation.dart';

part 'browser_runtime_driver_dispatch.dart';
part 'browser_runtime_driver_artifacts.dart';
part 'browser_runtime_driver_load_state.dart';

final class BrowserRuntimeDriver {
  BrowserRuntimeDriver({
    required RuntimeHostClient client,
    required BrowserSessionRegistry registry,
    required BrowserEngine engine,
    required this.appInstanceId,
    required this.driverInstanceId,
    DateTime Function()? now,
  }) : _client = client, // ignore: prefer_initializing_formals
       _registry = registry, // ignore: prefer_initializing_formals
       _engine = engine, // ignore: prefer_initializing_formals
       _now = now ?? _defaultNow;

  final RuntimeHostClient _client;
  final BrowserSessionRegistry _registry;
  final BrowserEngine _engine;
  final String appInstanceId;
  final String driverInstanceId;
  final DateTime Function() _now;
  final Map<String, int> _generations = <String, int>{};
  final Map<String, int> _documentGenerations = <String, int>{};
  final Map<String, int> _locallyInvalidatedDocuments = <String, int>{};
  final Map<String, _ReportedPage> _reportedPages = <String, _ReportedPage>{};
  final Map<String, _ActiveBrowserCall> _activeCalls =
      <String, _ActiveBrowserCall>{};
  StreamSubscription<RuntimeHostEvent>? _hostSubscription;
  StreamSubscription<BrowserRegistryEvent>? _registrySubscription;
  Future<void> _driverMutationTail = Future<void>.value();
  BrowserEngineCapabilities? _capabilities;
  var _started = false;
  var _disposed = false;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  @visibleForTesting
  int get debugActiveCallCount => _activeCalls.length;

  Future<void> start() async {
    if (_started) {
      return;
    }
    if (_disposed) {
      throw StateError('Browser runtime driver is disposed.');
    }
    _started = true;
    _hostSubscription = _client.runtimeEvents.listen(_onHostEvent);
    _registrySubscription = _registry.events.listen(_onRegistryEvent);
    _capabilities = await _engine.probeCapabilities();
    if (_disposed) {
      return;
    }
    await _queueDriverMutation(() async {
      if (_disposed) {
        return;
      }
      await _register();
      if (_disposed) {
        return;
      }
      await _syncPages();
    });
  }

  void _onHostEvent(RuntimeHostEvent event) {
    switch (event.name) {
      case aleraRuntimeHostConnectedEvent:
        unawaited(
          _queueDriverMutation(() async {
            if (_disposed) {
              return;
            }
            await _register();
            if (_disposed) {
              return;
            }
            await _syncPages();
          }).catchError((Object _) {}),
        );
      case 'browserDriverRequest':
        unawaited(_dispatchHostRequest(event.payload));
      case 'browserDriverCancel':
        final correlationId = event.payload['correlationId'];
        if (correlationId is String) {
          _activeCalls[correlationId]?.cancel();
        }
    }
  }

  void _onRegistryEvent(BrowserRegistryEvent event) {
    final handle = _registry.handleForPageId(event.pageId);
    if (handle?.isTransient == true) {
      return;
    }
    switch (event.kind) {
      case BrowserRegistryEventKind.opened:
        unawaited(_queueDriverMutation(_syncPages).catchError((Object _) {}));
      case BrowserRegistryEventKind.closed:
        _documentGenerations.remove(event.pageId);
        _locallyInvalidatedDocuments.remove(event.pageId);
        unawaited(_queueDriverMutation(_syncPages).catchError((Object _) {}));
      case BrowserRegistryEventKind.stateChanged:
        final state = event.state;
        final engineEvent = event.engineEvent;
        final navigationCompleted = engineEvent is BrowserNavigationFinished;
        final documentChanged = engineEvent is BrowserNavigationStarted;
        _ActiveBrowserCall? navigationCall;
        if (documentChanged) {
          navigationCall = _activeNavigationCall(event.pageId);
          final documentGeneration =
              (_documentGenerations[event.pageId] ?? 0) + 1;
          _documentGenerations[event.pageId] = documentGeneration;
          _locallyInvalidatedDocuments[event.pageId] = documentGeneration;
          for (final call in _activeCalls.values) {
            if (call.pageId == event.pageId &&
                !identical(call, navigationCall)) {
              call.cancel();
            }
          }
        }
        final documentGeneration = _documentGenerations[event.pageId] ?? 0;
        if (state != null &&
            (documentChanged ||
                navigationCompleted ||
                engineEvent is BrowserUrlChanged)) {
          unawaited(
            _queueDriverMutation(
              () => _reportPageChange(
                state,
                navigationCompleted: navigationCompleted,
                documentChanged: documentChanged,
                documentGeneration: documentGeneration,
                navigationCorrelationId: navigationCall?.correlationId,
              ),
            ).catchError((Object _) {}),
          );
        }
    }
  }

  Future<void> _register() async {
    final capabilities = _capabilities ?? await _engine.probeCapabilities();
    browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.driver.register', <String, Object?>{
        'appInstanceId': appInstanceId,
        'driverInstanceId': driverInstanceId,
        'engine': capabilities.engine,
        'platform': Platform.operatingSystem,
        'capabilities': _capabilityNames(capabilities),
      }),
      'Browser driver registration',
    );
    _generations.clear();
    _reportedPages.clear();
  }

  Future<void> _syncPages() async {
    final capabilities = _capabilities ?? await _engine.probeCapabilities();
    final pageCapabilities = _capabilityNames(capabilities);
    final persistentSessions = _registry.sessions
        .where(
          (handle) =>
              !handle.isTransient &&
              handle.state.engineAvailability ==
                  BrowserEngineAvailability.available,
        )
        .toList(growable: false);
    final response = browserRuntimeSuccessMap(
      await _client.runtimeRequest('browser.driver.sync', <String, Object?>{
        'driverInstanceId': driverInstanceId,
        'pages': <Map<String, Object?>>[
          for (final handle in persistentSessions)
            <String, Object?>{
              'pageId': handle.pageId,
              'workspaceId': handle.state.workspaceId,
              'profileId': handle.state.profileId,
              'url': handle.state.url.toString(),
              'title': _reportedBrowserTitle(handle.state),
              'documentGeneration': _documentGenerations[handle.pageId] ?? 0,
              'capabilities': pageCapabilities,
            },
        ],
      }),
      'Browser driver page synchronization',
    );
    _generations.clear();
    final acceptedPageIds = <String>{};
    final values = browserRuntimeList(response, 'pages');
    for (final value in values) {
      if (value is! Map || value['accepted'] != true) {
        continue;
      }
      final pageId = value['pageId'];
      final generation = value['generation'];
      if (pageId is String && generation is num) {
        _generations[pageId] = generation.toInt();
        acceptedPageIds.add(pageId);
      }
    }
    _locallyInvalidatedDocuments.removeWhere(
      (pageId, documentGeneration) =>
          acceptedPageIds.contains(pageId) &&
          _documentGenerations[pageId] == documentGeneration,
    );
    _reportedPages
      ..clear()
      ..addEntries(
        persistentSessions.map(
          (handle) =>
              MapEntry(handle.pageId, _ReportedPage.fromState(handle.state)),
        ),
      );
  }

  Future<void> _reportPageChange(
    BrowserPageState state, {
    required bool navigationCompleted,
    required bool documentChanged,
    required int documentGeneration,
    String? navigationCorrelationId,
  }) async {
    final next = _ReportedPage.fromState(state);
    if (!documentChanged &&
        !navigationCompleted &&
        _reportedPages[state.pageId] == next) {
      return;
    }
    var generation = _generations[state.pageId];
    if (generation == null) {
      await _syncPages();
      generation = _generations[state.pageId];
      if (generation == null) {
        return;
      }
    }
    final response = browserRuntimeSuccessMap(
      await _client
          .runtimeRequest('browser.driver.pageChanged', <String, Object?>{
            'driverInstanceId': driverInstanceId,
            'pageId': state.pageId,
            'generation': generation,
            'profileId': state.profileId,
            'url': state.url.toString(),
            'title': _reportedBrowserTitle(state),
            'documentChanged': documentChanged,
            'documentGeneration': documentGeneration,
            'navigationCompleted': navigationCompleted,
            'navigationCorrelationId': ?navigationCorrelationId,
          }),
      'Browser driver page change',
    );
    final page = response['page'];
    if (page is Map && page['generation'] is num) {
      final generation = (page['generation']! as num).toInt();
      _generations[state.pageId] = generation;
      final preservedCorrelationId =
          response['preservedNavigationCorrelationId'];
      if (preservedCorrelationId is String) {
        final preservedCall = _activeCalls[preservedCorrelationId];
        if (preservedCall != null &&
            preservedCall.pageId == state.pageId &&
            preservedCall.isNavigationCommand) {
          preservedCall.generation = generation;
        }
      }
    }
    if (documentChanged &&
        _locallyInvalidatedDocuments[state.pageId] == documentGeneration) {
      _locallyInvalidatedDocuments.remove(state.pageId);
    }
    _reportedPages[state.pageId] = next;
  }

  _ActiveBrowserCall? _activeNavigationCall(String pageId) {
    for (final call in _activeCalls.values) {
      if (call.pageId == pageId &&
          call.isNavigationCommand &&
          !call.cancelled) {
        return call;
      }
    }
    return null;
  }

  Future<T> _queueDriverMutation<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _driverMutationTail = _driverMutationTail.catchError((Object _) {}).then((
      _,
    ) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _hostSubscription?.cancel();
    await _registrySubscription?.cancel();
    for (final call in _activeCalls.values) {
      call.cancel();
    }
    if (_started) {
      try {
        await _queueDriverMutation(() async {
          browserRuntimeSuccessMap(
            await _client.runtimeRequest(
              'browser.driver.unregister',
              <String, Object?>{'driverInstanceId': driverInstanceId},
            ),
            'Browser driver unregistration',
          );
        });
      } on Object {
        // The runtime host may already be gone during application shutdown.
      }
    }
  }
}

final class _ReportedPage {
  const _ReportedPage({
    required this.profileId,
    required this.url,
    required this.title,
  });

  factory _ReportedPage.fromState(BrowserPageState state) => _ReportedPage(
    profileId: state.profileId,
    url: state.url.toString(),
    title: _reportedBrowserTitle(state),
  );

  final String profileId;
  final String url;
  final String? title;

  @override
  bool operator ==(Object other) =>
      other is _ReportedPage &&
      profileId == other.profileId &&
      url == other.url &&
      title == other.title;

  @override
  int get hashCode => Object.hash(profileId, url, title);
}

String? _reportedBrowserTitle(BrowserPageState state) {
  final url = state.url.toString();
  if (url != 'about:blank' && !isPersistableBrowserUrl(url)) {
    return null;
  }
  return normalizeAleraBrowserTitle(state.title);
}

final class _ActiveBrowserCall {
  _ActiveBrowserCall({
    required this.correlationId,
    required this.pageId,
    required this.generation,
    required this.method,
    required this.deadline,
  });

  final String correlationId;
  final String pageId;
  int generation;
  final String method;
  final DateTime deadline;
  final Completer<void> _cancellation = Completer<void>();

  bool get isNavigationCommand => _isNavigationCommand(method);

  bool get cancelled => _cancellation.isCompleted;

  Future<void> get cancellation => _cancellation.future;

  void cancel() {
    if (!_cancellation.isCompleted) {
      _cancellation.complete();
    }
  }
}

bool _isNavigationCommand(String method) => switch (method) {
  'browser.navigate' ||
  'browser.back' ||
  'browser.forward' ||
  'browser.reload' => true,
  _ => false,
};

List<String> _capabilityNames(BrowserEngineCapabilities value) {
  return <String>[
    if (value.meetsStableGate) 'stableGate',
    if (value.navigation) 'navigation',
    if (value.javascript) 'javascript',
    if (value.fullCookies) 'cookies',
    if (value.domSnapshot) 'domSnapshot',
    if (value.domActions) 'domActions',
    if (value.viewportScreenshot) 'viewportScreenshot',
    if (value.fullPageScreenshot) 'fullPageScreenshot',
    if (value.pdf) 'pdf',
  ];
}
