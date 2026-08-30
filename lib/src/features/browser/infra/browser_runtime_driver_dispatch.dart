part of 'browser_runtime_driver.dart';

extension _BrowserRuntimeDriverDispatch on BrowserRuntimeDriver {
  Future<void> _dispatchHostRequest(Map<String, Object?> payload) async {
    if (payload['driverInstanceId'] != driverInstanceId) {
      return;
    }
    final correlationId = payload['correlationId'];
    final pageId = payload['pageId'];
    final generation = payload['generation'];
    final method = payload['method'];
    final deadlineAt = payload['deadlineAt'];
    if (correlationId is! String ||
        pageId is! String ||
        generation is! num ||
        method is! String ||
        deadlineAt is! num) {
      return;
    }
    final call = _ActiveBrowserCall(
      correlationId: correlationId,
      pageId: pageId,
      generation: generation.toInt(),
      method: method,
      deadline: DateTime.fromMillisecondsSinceEpoch(
        deadlineAt.toInt(),
        isUtc: true,
      ),
    );
    _activeCalls[correlationId] = call;
    Map<String, Object?> outcome;
    final rawParams = payload['params'];
    final params = rawParams is Map
        ? Map<String, Object?>.from(rawParams)
        : const <String, Object?>{};
    try {
      outcome = await _execute(call, method, params);
    } catch (error) {
      outcome = _browserFailureOutcome(error);
    }
    if (_isBrowserArtifactMethod(method) &&
        (call.cancelled || outcome['ok'] != true)) {
      await _removeBrowserArtifact(params['destinationPath']);
    }
    if (call.isNavigationCommand) {
      try {
        await _queueDriverMutation(() async {
          if (call.cancelled || !identical(_activeCalls[correlationId], call)) {
            return;
          }
          await _sendDriverCompletion(call, outcome);
        });
      } finally {
        if (identical(_activeCalls[correlationId], call)) {
          _activeCalls.remove(correlationId);
        }
      }
      return;
    }
    final wasActive = _activeCalls.remove(correlationId) != null;
    if (call.cancelled || !wasActive) {
      return;
    }
    await _sendDriverCompletion(call, outcome);
  }

  Future<void> _sendDriverCompletion(
    _ActiveBrowserCall call,
    Map<String, Object?> outcome,
  ) async {
    try {
      browserRuntimeSuccessMap(
        await _client.runtimeRequest(
          'browser.driver.complete',
          <String, Object?>{
            'driverInstanceId': driverInstanceId,
            'correlationId': call.correlationId,
            'pageId': call.pageId,
            'generation': call.generation,
            'outcome': outcome,
          },
        ),
        'Browser driver completion',
      );
    } on Object {
      // Stale completions are expected after cancellation or page changes.
    }
  }

  Future<Map<String, Object?>> _execute(
    _ActiveBrowserCall call,
    String method,
    Map<String, Object?> params,
  ) async {
    _validateCall(call);
    final handle = _registry.handleForPageId(call.pageId);
    if (handle == null ||
        handle.state.engineAvailability !=
            BrowserEngineAvailability.available) {
      throw BrowserFailure(
        code: BrowserErrorCode.pageNotFound,
        message: 'Browser page ${call.pageId} is not available.',
        recoverable: true,
      );
    }
    final visibilityReason = _visibilityReason(method);
    final visibility = visibilityReason == null
        ? null
        : handle.acquireVisibility(visibilityReason);
    final guard = BrowserOperationGuard(
      deadline: call.deadline,
      cancellation: call.cancellation,
      isCancelled: () => call.cancelled,
      now: _now,
    );
    try {
      if (visibility != null) {
        await guard.run(visibility.ready);
      }
      _validateCall(call);
      return await _executeWithHandle(call, handle, method, params, guard);
    } finally {
      await visibility?.dispose();
    }
  }

  Future<Map<String, Object?>> _executeWithHandle(
    _ActiveBrowserCall call,
    BrowserSessionHandle handle,
    String method,
    Map<String, Object?> params,
    BrowserOperationGuard guard,
  ) async {
    _validateCall(call);
    switch (method) {
      case 'browser.navigate':
        final target = await handle.loadUrl(
          _requiredString(params, 'url'),
          guard: guard,
        );
        return _success(<String, Object?>{
          'url': target.url.toString(),
          'kind': target.kind.name,
        });
      case 'browser.back':
        await handle.back(guard: guard);
        return _success();
      case 'browser.forward':
        await handle.forward(guard: guard);
        return _success();
      case 'browser.reload':
        await handle.reload(guard: guard);
        return _success();
      case 'browser.stop':
        await handle.stop(guard: guard);
        return _success();
      case 'browser.snapshot':
        final snapshot = await handle.snapshot(
          interactiveOnly: params['interactiveOnly'] == true,
          maxNodes: _snapshotMaxNodes(params),
          guard: guard,
        );
        return _success(<String, Object?>{'snapshot': snapshot.toJson()});
      case 'browser.ref.click':
      case 'browser.ref.fill':
      case 'browser.ref.type':
      case 'browser.ref.select':
      case 'browser.ref.focus':
      case 'browser.ref.hover':
        await handle.performAction(
          _action(method, call.pageId, params),
          guard: guard,
        );
        return _success();
      case 'browser.ref.scroll':
        final ref = params['ref'];
        if (ref is String && ref.isNotEmpty) {
          await handle.performAction(
            _action('browser.ref.scroll', call.pageId, params),
            guard: guard,
          );
        } else {
          final x = (params['x'] as num?)?.toDouble() ?? 0;
          final y = (params['y'] as num?)?.toDouble() ?? 0;
          await handle.evaluateJavaScript(
            'window.scrollBy($x, $y)',
            guard: guard,
          );
        }
        return _success();
      case 'browser.wait':
        return _waitForBrowser(call, handle, params, guard);
      case 'browser.eval':
        final result = await handle.evaluateJavaScript(
          _requiredString(params, 'expression'),
          guard: guard,
        );
        return _success(<String, Object?>{'result': _jsonValue(result)});
      case 'browser.screenshot':
        final artifact = await handle.captureScreenshot(
          destinationPath: _requiredString(params, 'destinationPath'),
          expiresAt: _requiredDateTime(params, 'expiresAt'),
          fullPage: params['fullPage'] == true,
          guard: guard,
        );
        return _success(<String, Object?>{'artifact': artifact.toJson()});
      case 'browser.pdf':
        final artifact = await handle.printToPdf(
          destinationPath: _requiredString(params, 'destinationPath'),
          expiresAt: _requiredDateTime(params, 'expiresAt'),
          guard: guard,
        );
        return _success(<String, Object?>{'artifact': artifact.toJson()});
      case 'browser.cookies.list':
        final cookies = await handle.getCookies(guard: guard);
        return _success(<String, Object?>{
          'cookies': <Map<String, Object?>>[
            for (final cookie in cookies) cookie.toJson(),
          ],
        });
      case 'browser.cookies.delete':
        await handle.deleteCookies(
          name: params['name'] as String?,
          domain: params['domain'] as String?,
          path: params['path'] as String?,
          guard: guard,
        );
        return _success();
      case 'browser.cookies.clear':
        await handle.deleteCookies(guard: guard);
        return _success();
      default:
        throw BrowserFailure(
          code: BrowserErrorCode.unsupportedCapability,
          message: 'Unsupported browser driver method: $method.',
        );
    }
  }

  Future<Map<String, Object?>> _waitForBrowser(
    _ActiveBrowserCall call,
    BrowserSessionHandle handle,
    Map<String, Object?> params,
    BrowserOperationGuard guard,
  ) async {
    final expectedUrl = params['url'] as String?;
    final expectedText = params['text'] as String?;
    final expectedRef = params['ref'] as String?;
    final expectedLoadPhase = _browserExpectedLoadPhase(params['loadState']);
    while (_now().isBefore(call.deadline) && !call.cancelled) {
      _validateCall(call);
      final state = handle.state;
      final urlMatches =
          expectedUrl == null || state.url.toString().contains(expectedUrl);
      final loadMatches = _browserLoadPhaseReached(
        state.loadPhase,
        expectedLoadPhase,
      );
      BrowserAutomationSnapshot? snapshot;
      var contentMatches = expectedText == null && expectedRef == null;
      if (!contentMatches && urlMatches && loadMatches) {
        snapshot = await handle.snapshot(guard: guard);
        contentMatches = snapshot.nodes.any((node) {
          final refMatches =
              expectedRef == null || node.target.ref == expectedRef;
          final textMatches =
              expectedText == null ||
              node.name.contains(expectedText) ||
              (node.value?.contains(expectedText) ?? false);
          return refMatches && textMatches;
        });
      }
      if (urlMatches && loadMatches && contentMatches) {
        return _success(<String, Object?>{
          'url': state.url.toString(),
          'loadState': state.loadPhase.name,
          if (snapshot != null) 'snapshot': snapshot.toJson(),
        });
      }
      final remaining = call.deadline.difference(_now());
      if (remaining <= Duration.zero) {
        break;
      }
      await _nextPageState(
        handle.stateListenable,
        remaining < const Duration(milliseconds: 100)
            ? remaining
            : const Duration(milliseconds: 100),
      );
    }
    if (call.cancelled) {
      throw const BrowserFailure(
        code: BrowserErrorCode.timeout,
        message: 'The browser wait was cancelled.',
        recoverable: true,
      );
    }
    throw TimeoutException('The browser wait condition was not met.');
  }

  void _validateCall(_ActiveBrowserCall call) {
    if (!_now().isBefore(call.deadline)) {
      throw TimeoutException('The browser request deadline has passed.');
    }
    if (call.cancelled ||
        _generations[call.pageId] != call.generation ||
        _locallyInvalidatedDocuments.containsKey(call.pageId)) {
      throw BrowserFailure(
        code: BrowserErrorCode.staleAutomationReference,
        message: 'The browser page changed before the request could run.',
        recoverable: true,
      );
    }
  }
}

int _snapshotMaxNodes(Map<String, Object?> params) {
  final value = (params['maxNodes'] as num?)?.toInt() ?? 500;
  if (value < 1 || value > 5000) {
    throw const FormatException(
      'Browser snapshot maxNodes must be between 1 and 5000.',
    );
  }
  return value;
}

BrowserVisibilityReason? _visibilityReason(String method) {
  if (method == 'browser.screenshot' || method == 'browser.pdf') {
    return BrowserVisibilityReason.capture;
  }
  if (method == 'browser.snapshot' ||
      method == 'browser.wait' ||
      method == 'browser.eval' ||
      method.startsWith('browser.ref.')) {
    return BrowserVisibilityReason.automation;
  }
  return null;
}

BrowserAutomationAction _action(
  String method,
  String pageId,
  Map<String, Object?> params,
) {
  final kind = switch (method) {
    'browser.ref.click' => BrowserAutomationActionKind.click,
    'browser.ref.fill' => BrowserAutomationActionKind.fill,
    'browser.ref.type' => BrowserAutomationActionKind.type,
    'browser.ref.select' => BrowserAutomationActionKind.select,
    'browser.ref.focus' => BrowserAutomationActionKind.focus,
    'browser.ref.hover' => BrowserAutomationActionKind.hover,
    'browser.ref.scroll' => BrowserAutomationActionKind.scroll,
    _ => throw FormatException('Unsupported browser ref method: $method'),
  };
  final value = params['text'] ?? params['value'];
  return BrowserAutomationAction(
    kind: kind,
    target: BrowserAutomationRef(
      pageId: pageId,
      snapshotId: _requiredString(params, 'snapshotId'),
      ref: _requiredString(params, 'ref'),
    ),
    value: value as String?,
    options: <String, Object?>{
      if (method == 'browser.ref.select' && value is String)
        'values': <String>[value],
    },
  );
}

Future<void> _nextPageState(
  ValueListenable<BrowserPageState> state,
  Duration timeout,
) {
  final completer = Completer<void>();
  late VoidCallback listener;
  listener = () {
    state.removeListener(listener);
    if (!completer.isCompleted) {
      completer.complete();
    }
  };
  state.addListener(listener);
  return completer.future.timeout(
    timeout,
    onTimeout: () {
      state.removeListener(listener);
    },
  );
}

Map<String, Object?> _success([
  Map<String, Object?> values = const <String, Object?>{},
]) => <String, Object?>{'ok': true, ...values};

Map<String, Object?> _browserFailureOutcome(Object error) {
  final failure = switch (error) {
    BrowserFailure value => value,
    TimeoutException value => BrowserFailure(
      code: BrowserErrorCode.timeout,
      message: value.message ?? 'The browser operation timed out.',
      recoverable: true,
    ),
    FormatException value => BrowserFailure(
      code: BrowserErrorCode.invalidPayload,
      message: value.message,
      recoverable: true,
    ),
    _ => BrowserFailure(
      code: BrowserErrorCode.unknown,
      message: error.toString(),
      recoverable: true,
    ),
  };
  return <String, Object?>{
    'ok': false,
    'error': <String, Object?>{
      'code': _snakeCase(failure.code.name),
      'message': failure.message,
      'nextSteps': failure.details['nextSteps'] ?? const <String>[],
    },
  };
}

String _requiredString(Map<String, Object?> value, String key) {
  final item = value[key];
  if (item is String && item.trim().isNotEmpty) {
    return item;
  }
  throw FormatException('$key is required.');
}

DateTime _requiredDateTime(Map<String, Object?> value, String key) {
  final result = DateTime.tryParse(value[key] as String? ?? '');
  if (result == null) {
    throw FormatException('$key must be an RFC3339 timestamp.');
  }
  return result.toUtc();
}

Object? _jsonValue(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  try {
    jsonEncode(value);
    return value;
  } on Object {
    return value.toString();
  }
}

String _snakeCase(String value) {
  return value.replaceAllMapped(
    RegExp('([a-z0-9])([A-Z])'),
    (match) => '${match[1]}_${match[2]!.toLowerCase()}',
  );
}
