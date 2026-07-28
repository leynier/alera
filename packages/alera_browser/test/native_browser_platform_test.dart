import 'dart:async';

import 'package:alera_browser/src/browser_callbacks.dart';
import 'package:alera_browser/src/browser_cookie_import.dart';
import 'package:alera_browser/src/browser_errors.dart';
import 'package:alera_browser/src/browser_events.dart';
import 'package:alera_browser/src/browser_models.dart';
import 'package:alera_browser/src/native_browser_channel.dart';
import 'package:alera_browser/src/native_browser_platform.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('failed native close preserves the page for retry', () async {
    const methodChannel = MethodChannel(
      'dev.leynier.alera/browser/native-platform-close-test',
    );
    const eventChannel = EventChannel(
      'dev.leynier.alera/browser/native-platform-close-test/events',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final listening = Completer<void>();
    var closeShouldFail = true;
    var closeCalls = 0;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'page.create':
          return <String, Object?>{'id': 'page'};
        case 'page.close':
          closeCalls++;
          if (closeShouldFail) {
            throw PlatformException(
              code: 'close_failed',
              message: 'Native close failed.',
            );
          }
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'dev.leynier.alera/browser/native-platform-close-test/events',
      ),
      (call) async {
        if (call.method == 'listen' && !listening.isCompleted) {
          listening.complete();
        }
        return null;
      },
    );
    final platform = NativeAleraBrowserPlatform(
      callbacks: const AleraBrowserCallbacks(),
      channel: const AleraBrowserNativeChannel(
        methodChannel: methodChannel,
        eventChannel: eventChannel,
      ),
    );
    await listening.future;
    await platform.createPage(
      const AleraBrowserPageOptions(id: 'page', profileId: 'default'),
    );

    await expectLater(
      platform.closePage('page'),
      throwsA(isA<AleraBrowserNativeError>()),
    );
    closeShouldFail = false;
    await platform.closePage('page');
    await platform.closePage('page');

    expect(closeCalls, 2);
    await platform.dispose();
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'dev.leynier.alera/browser/native-platform-close-test/events',
      ),
      null,
    );
  });

  test('native download lifecycle event is decoded', () async {
    const methodChannel = MethodChannel(
      'dev.leynier.alera/browser/native-platform-event-test',
    );
    const eventChannel = EventChannel(
      'dev.leynier.alera/browser/native-platform-event-test/events',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final listening = Completer<void>();
    messenger.setMockMethodCallHandler(methodChannel, (_) async => null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'dev.leynier.alera/browser/native-platform-event-test/events',
      ),
      (call) async {
        if (call.method == 'listen' && !listening.isCompleted) {
          listening.complete();
        }
        return null;
      },
    );
    final platform = NativeAleraBrowserPlatform(
      callbacks: const AleraBrowserCallbacks(),
      channel: const AleraBrowserNativeChannel(
        methodChannel: methodChannel,
        eventChannel: eventChannel,
      ),
      now: () => DateTime.utc(2026, 7, 27),
    );
    await listening.future;
    final nextEvent = platform.events
        .where((event) => event is AleraBrowserDownloadChanged)
        .cast<AleraBrowserDownloadChanged>()
        .first;

    await messenger.handlePlatformMessage(
      'dev.leynier.alera/browser/native-platform-event-test/events',
      const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
        'type': 'downloadChanged',
        'pageId': 'page',
        'downloadId': 'download-1',
        'state': 'inProgress',
        'receivedBytes': 12,
        'totalBytes': 24,
        'suggestedFileName': 'report.pdf',
        'destinationPath': '/tmp/report.pdf',
      }),
      (_) {},
    );

    final event = await nextEvent;
    expect(event.pageId, 'page');
    expect(event.downloadId, 'download-1');
    expect(event.state, AleraBrowserDownloadState.inProgress);
    expect(event.receivedBytes, 12);
    expect(event.totalBytes, 24);
    expect(event.suggestedFileName, 'report.pdf');
    expect(event.destinationPath, '/tmp/report.pdf');
    expect(event.occurredAt, DateTime.utc(2026, 7, 27));

    final navigation = platform.events
        .where((event) => event is AleraBrowserNavigationFinished)
        .cast<AleraBrowserNavigationFinished>()
        .first;
    await messenger.handlePlatformMessage(
      'dev.leynier.alera/browser/native-platform-event-test/events',
      const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
        'type': 'navigationFinished',
        'pageId': 'page',
        'url': 'https://example.com',
        'title': '\u0000Example\n',
        'canGoBack': true,
        'canGoForward': false,
      }),
      (_) {},
    );
    final navigationEvent = await navigation;
    expect(navigationEvent.title, 'Example');
    expect(navigationEvent.canGoBack, isTrue);
    expect(navigationEvent.canGoForward, isFalse);

    final committed = platform.events
        .where((event) => event is AleraBrowserNavigationCommitted)
        .cast<AleraBrowserNavigationCommitted>()
        .first;
    await messenger.handlePlatformMessage(
      'dev.leynier.alera/browser/native-platform-event-test/events',
      const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
        'type': 'navigationCommitted',
        'pageId': 'page',
        'url': 'https://example.com/committed',
      }),
      (_) {},
    );
    final committedEvent = await committed;
    expect(committedEvent.pageId, 'page');
    expect(committedEvent.url, Uri.parse('https://example.com/committed'));
    expect(committedEvent.occurredAt, DateTime.utc(2026, 7, 27));

    await platform.dispose();
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'dev.leynier.alera/browser/native-platform-event-test/events',
      ),
      null,
    );
  });

  test('native TLS requests decode certificate metadata and resolve', () async {
    const methodChannel = MethodChannel(
      'dev.leynier.alera/browser/native-platform-tls-test',
    );
    const eventChannel = EventChannel(
      'dev.leynier.alera/browser/native-platform-tls-test/events',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final listening = Completer<void>();
    final received = Completer<AleraBrowserTlsError>();
    final resolved = Completer<Map<Object?, Object?>>();
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'decision.resolve' && !resolved.isCompleted) {
        resolved.complete(call.arguments as Map<Object?, Object?>);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'dev.leynier.alera/browser/native-platform-tls-test/events',
      ),
      (call) async {
        if (call.method == 'listen' && !listening.isCompleted) {
          listening.complete();
        }
        return null;
      },
    );
    final platform = NativeAleraBrowserPlatform(
      callbacks: AleraBrowserCallbacks(
        onTlsError: (error) async {
          received.complete(error);
          return AleraBrowserTlsDecision.proceed;
        },
      ),
      channel: const AleraBrowserNativeChannel(
        methodChannel: methodChannel,
        eventChannel: eventChannel,
      ),
    );
    await listening.future;

    await messenger.handlePlatformMessage(
      'dev.leynier.alera/browser/native-platform-tls-test/events',
      const StandardMethodCodec().encodeSuccessEnvelope(<String, Object?>{
        'type': 'tlsRequest',
        'decisionId': 'decision-1',
        'pageId': 'page',
        'url': 'https://service.local',
        'host': 'service.local',
        'fingerprintSha256':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'description': 'Unknown issuer',
        'subject': 'Local Service',
        'issuer': 'Development CA',
        'validFrom': 1785196800000,
        'validTo': '2026-08-27T00:00:00.000Z',
        'errors': <String>['untrustedIssuer', 'futureError'],
      }),
      (_) {},
    );

    final error = await received.future;
    expect(error.pageId, 'page');
    expect(error.url, Uri.parse('https://service.local'));
    expect(error.host, 'service.local');
    expect(error.subject, 'Local Service');
    expect(error.issuer, 'Development CA');
    expect(
      error.validFrom,
      DateTime.fromMillisecondsSinceEpoch(1785196800000, isUtc: true),
    );
    expect(error.validTo, DateTime.utc(2026, 8, 27));
    expect(error.errors, <AleraBrowserTlsErrorType>{
      AleraBrowserTlsErrorType.untrustedIssuer,
      AleraBrowserTlsErrorType.other,
    });
    final resolution = await resolved.future;
    expect(resolution['decisionId'], 'decision-1');
    expect(resolution['decision'], 'proceed');
    expect(resolution['targetPageId'], isNull);
    expect(resolution['destinationPath'], isNull);

    await platform.dispose();
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'dev.leynier.alera/browser/native-platform-tls-test/events',
      ),
      null,
    );
  });

  test(
    'cookie source profiles decode and selected profile serializes',
    () async {
      const methodChannel = MethodChannel(
        'dev.leynier.alera/browser/native-platform-import-test',
      );
      const eventChannel = EventChannel(
        'dev.leynier.alera/browser/native-platform-import-test/events',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map<Object?, Object?>? importArguments;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'cookieImport.probe') {
          return <Map<String, Object?>>[
            <String, Object?>{
              'source': 'chrome',
              'supported': true,
              'available': true,
              'profileNames': <String>['Default', 'Profile 1'],
            },
          ];
        }
        if (call.method == 'cookieImport.run') {
          importArguments = call.arguments as Map<Object?, Object?>;
          return <String, Object?>{
            'outcome': 'imported',
            'importedCount': 1,
            'skippedCount': 0,
          };
        }
        return null;
      });
      messenger.setMockMethodCallHandler(
        const MethodChannel(
          'dev.leynier.alera/browser/native-platform-import-test/events',
        ),
        (_) async => null,
      );
      final platform = NativeAleraBrowserPlatform(
        callbacks: const AleraBrowserCallbacks(),
        channel: const AleraBrowserNativeChannel(
          methodChannel: methodChannel,
          eventChannel: eventChannel,
        ),
      );

      final statuses = await platform.probeCookieImportSources();
      expect(statuses.single.profileNames, <String>['Default', 'Profile 1']);
      await platform.importCookies(
        AleraBrowserNativeCookieImportRequest(
          profileId: 'target',
          gestureToken: AleraBrowserUserGestureToken.internal(
            'gesture',
            DateTime.utc(2026, 7, 27),
          ),
          source: AleraBrowserCookieImportSource.chrome,
          sourceProfileName: 'Profile 1',
        ),
      );

      expect(importArguments?['source'], 'chrome');
      expect(importArguments?['sourceProfileName'], 'Profile 1');
      expect(importArguments?.containsKey('json'), isFalse);
      await platform.dispose();
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel(
          'dev.leynier.alera/browser/native-platform-import-test/events',
        ),
        null,
      );
    },
  );
}
