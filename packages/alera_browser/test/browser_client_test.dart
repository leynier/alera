import 'dart:async';

import 'package:alera_browser/alera_browser.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'attachment leases only cross the native boundary at zero and one',
    () async {
      final platform = _RecordingPlatform();
      final client = AleraBrowserClient(platform: platform);

      await client.attachPage('page', leaseId: 'visible');
      await client.attachPage('page', leaseId: 'visible');
      await client.attachPage('page', leaseId: 'automation');
      await client.detachPage('page', leaseId: 'visible');

      expect(platform.attachCalls, 1);
      expect(platform.detachCalls, 0);

      await client.detachPage('page', leaseId: 'automation');
      await client.detachPage('page', leaseId: 'automation');

      expect(platform.detachCalls, 1);
    },
  );

  test('failed native attachment transitions remain retryable', () async {
    final platform = _RecordingPlatform()
      ..attachFailuresRemaining = 1
      ..detachFailuresRemaining = 1;
    final client = AleraBrowserClient(platform: platform);

    await expectLater(client.attachPage('page'), throwsStateError);
    await client.attachPage('page');
    expect(platform.attachCalls, 2);

    await expectLater(client.detachPage('page'), throwsStateError);
    await client.detachPage('page');
    expect(platform.detachCalls, 2);
  });

  test('concurrent lease transitions are serialized per page', () async {
    final platform = _RecordingPlatform();
    final attachGate = Completer<void>();
    platform.attachGate = attachGate;
    final client = AleraBrowserClient(platform: platform);

    final visible = client.attachPage('page', leaseId: 'visible');
    final automation = client.attachPage('page', leaseId: 'automation');
    await Future.pause(.zero);
    expect(platform.attachCalls, 1);

    attachGate.complete();
    await Future.wait(<Future<void>>[visible, automation]);
    await client.detachPage('page', leaseId: 'visible');
    expect(platform.detachCalls, 0);
    await client.detachPage('page', leaseId: 'automation');
    expect(platform.detachCalls, 1);
  });

  test('dispose waits for an active attachment transition', () async {
    final platform = _RecordingPlatform();
    final attachGate = Completer<void>();
    platform.attachGate = attachGate;
    final client = AleraBrowserClient(platform: platform);

    final attach = client.attachPage('page');
    final dispose = client.dispose();
    await Future.pause(.zero);
    expect(platform.disposeCalls, 0);

    attachGate.complete();
    await attach;
    await dispose;
    expect(platform.disposeCalls, 1);
    await expectLater(client.attachPage('page'), throwsStateError);
  });

  test('cookie discovery requires a fresh, unused gesture', () async {
    var now = DateTime.utc(2026, 7, 27);
    final platform = _RecordingPlatform();
    final client = AleraBrowserClient(platform: platform, now: () => now);
    final token = client.beginCookieImportGesture();

    await client.probeCookieImportSources(token);
    expect(platform.cookieProbeCalls, 1);
    expect(() => client.probeCookieImportSources(token), throwsStateError);

    final stale = client.beginCookieImportGesture();
    now = now.add(const Duration(seconds: 16));
    expect(() => client.probeCookieImportSources(stale), throwsStateError);
  });

  testWidgets('browser view owns an independent attachment lease', (
    tester,
  ) async {
    final platform = _RecordingPlatform();
    final client = AleraBrowserClient(platform: platform);

    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: AleraBrowserView(client: client, pageId: 'page'),
      ),
    );
    await tester.pump();
    expect(platform.attachCalls, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(platform.detachCalls, 1);
  });
}

final class _RecordingPlatform implements AleraBrowserPlatform {
  final StreamController<AleraBrowserEvent> _events =
      StreamController<AleraBrowserEvent>.broadcast();

  int attachCalls = 0;
  int detachCalls = 0;
  int cookieProbeCalls = 0;
  int disposeCalls = 0;
  int attachFailuresRemaining = 0;
  int detachFailuresRemaining = 0;
  Completer<void>? attachGate;

  @override
  Stream<AleraBrowserEvent> get events => _events.stream;

  @override
  Future<void> attachPage(String pageId) async {
    attachCalls += 1;
    await attachGate?.future;
    if (attachFailuresRemaining > 0) {
      attachFailuresRemaining -= 1;
      throw StateError('attach failed');
    }
  }

  @override
  Future<void> detachPage(String pageId) async {
    detachCalls += 1;
    if (detachFailuresRemaining > 0) {
      detachFailuresRemaining -= 1;
      throw StateError('detach failed');
    }
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  @override
  Widget buildPageView(String pageId, {Key? key}) => SizedBox(key: key);

  @override
  Future<List<AleraBrowserCookieImportSourceStatus>>
  probeCookieImportSources() async {
    cookieProbeCalls += 1;
    return const <AleraBrowserCookieImportSourceStatus>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
