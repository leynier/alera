import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _original = 'rejected: non-fast-forward';
const String _clarified =
    'The push was rejected because the remote has new commits. Pull, then '
    'push again.';
const String _clarifying = 'Clarifying with AI Assist…';
const String _clarifiedCaption = 'Clarified by AI Assist';

void main() {
  testWidgets('errors and warnings default to the long toast duration', (
    tester,
  ) async {
    final published = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(published.add);
    addTearDown(subscription.cancel);

    AleraToast.publish(message: 'Failed', tone: .error);
    AleraToast.publish(message: 'Careful', tone: .warning);
    AleraToast.publish(message: 'Saved', tone: .success);
    AleraToast.publish(message: 'Heads up');
    AleraToast.publish(
      message: 'Custom',
      tone: .error,
      duration: const Duration(seconds: 1),
    );
    await tester.pump();

    expect(published.map((toast) => toast.duration), <Duration>[
      AleraTokens.toastLongDuration,
      AleraTokens.toastLongDuration,
      AleraTokens.toastDuration,
      AleraTokens.toastDuration,
      const Duration(seconds: 1),
    ]);
    expect(AleraToast.longDuration, AleraTokens.toastLongDuration);
  });

  testWidgets('an error toast stays up for the long duration', (tester) async {
    await _pumpHost(tester);

    AleraToast.publish(message: 'Push failed', tone: .error);
    await tester.pump();

    await tester.pump(AleraTokens.toastDuration + AleraTokens.durationMid);
    expect(find.text('Push failed'), findsOneWidget);

    await tester.pump(
      AleraTokens.toastLongDuration - AleraTokens.toastDuration,
    );
    await tester.pump(AleraTokens.durationMid);
    expect(find.text('Push failed'), findsNothing);
  });

  testWidgets(
    'shows the clarified error with a caption and copies the original',
    (tester) async {
      final copied = _captureClipboard(tester);
      final pending = Completer<String?>();
      final requested = <String>[];
      await _pumpHost(
        tester,
        clarifyError: (message) {
          requested.add(message);
          return pending.future;
        },
      );

      AleraToast.publish(
        message: _original,
        tone: .error,
        duration: const Duration(seconds: 2),
      );
      await tester.pump();

      expect(requested, <String>[_original]);
      expect(find.text(_original), findsOneWidget);
      expect(find.text(_clarifying), findsOneWidget);
      expect(find.text('Copy Original'), findsNothing);

      pending.complete('  $_clarified  ');
      // One pump runs the continuation, the next renders its setState.
      await tester.pump();
      await tester.pump();

      expect(find.text(_original), findsNothing);
      expect(find.text(_clarified), findsOneWidget);
      expect(find.text(_clarifying), findsNothing);
      expect(find.text(_clarifiedCaption), findsOneWidget);
      expect(find.text('Copy Original'), findsOneWidget);

      await tester.tap(find.text('Copy Original'));
      await tester.pump();
      expect(copied, <String>[_original]);

      await tester.pump(AleraTokens.durationMid);
      expect(find.text(_clarified), findsNothing);
    },
  );

  testWidgets('the clarified toast dismisses after its own duration', (
    tester,
  ) async {
    await _pumpHost(tester, clarifyError: (_) async => _clarified);

    AleraToast.publish(
      message: _original,
      tone: .error,
      duration: const Duration(seconds: 2),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text(_clarified), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(AleraTokens.durationMid);
    expect(find.text(_clarified), findsNothing);
  });

  testWidgets('the toast is not dismissed while the clarification runs', (
    tester,
  ) async {
    final pending = Completer<String?>();
    await _pumpHost(tester, clarifyError: (_) => pending.future);

    AleraToast.publish(
      message: _original,
      tone: .error,
      duration: const Duration(milliseconds: 20),
    );
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));

    expect(find.text(_original), findsOneWidget);
    expect(find.text(_clarifying), findsOneWidget);

    pending.complete(null);
    await tester.pump();
    await tester.pump();
    expect(find.text(_original), findsOneWidget);
    expect(find.text(_clarifying), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(AleraTokens.durationMid);
    expect(find.text(_original), findsNothing);
  });

  testWidgets('keeps the original text when the clarifier returns null', (
    tester,
  ) async {
    await _pumpHost(tester, clarifyError: (_) async => null);

    AleraToast.publish(
      message: _original,
      tone: .error,
      duration: const Duration(milliseconds: 20),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(_original), findsOneWidget);
    expect(find.text(_clarifying), findsNothing);
    expect(find.text(_clarifiedCaption), findsNothing);
    expect(find.text('Copy Original'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(AleraTokens.durationMid);
  });

  testWidgets('keeps the original text when the clarifier throws', (
    tester,
  ) async {
    await _pumpHost(
      tester,
      clarifyError: (_) async => throw StateError('agent failed'),
    );

    AleraToast.publish(
      message: _original,
      tone: .error,
      duration: const Duration(milliseconds: 20),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(_original), findsOneWidget);
    expect(find.text(_clarifying), findsNothing);
    expect(find.text('Copy Original'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(AleraTokens.durationMid);
  });

  testWidgets('keeps the original text when the rewrite is unchanged', (
    tester,
  ) async {
    await _pumpHost(tester, clarifyError: (message) async => ' $message ');

    AleraToast.publish(
      message: _original,
      tone: .error,
      duration: const Duration(milliseconds: 20),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text(_original), findsOneWidget);
    expect(find.text(_clarifiedCaption), findsNothing);
    expect(find.text('Copy Original'), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(AleraTokens.durationMid);
  });

  testWidgets('an error toast with its own action is not clarified', (
    tester,
  ) async {
    var calls = 0;
    await _pumpHost(
      tester,
      clarifyError: (_) async {
        calls++;
        return _clarified;
      },
    );

    AleraToast.publish(
      message: _original,
      tone: .error,
      duration: const Duration(milliseconds: 20),
      actionLabel: 'Open Host',
      onAction: () {},
    );
    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.text(_original), findsOneWidget);
    expect(find.text('Open Host'), findsOneWidget);
    expect(find.text(_clarifying), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(AleraTokens.durationMid);
  });

  testWidgets('only error toasts are clarified', (tester) async {
    var calls = 0;
    await _pumpHost(
      tester,
      clarifyError: (_) async {
        calls++;
        return _clarified;
      },
    );

    for (final tone in <AleraToastTone>[.info, .success, .warning]) {
      AleraToast.publish(
        message: 'Toast ${tone.name}',
        tone: tone,
        duration: const Duration(milliseconds: 20),
      );
    }
    await tester.pump();
    await tester.pump();

    expect(calls, 0);
    expect(find.text(_clarifying), findsNothing);
    expect(find.text('Toast warning'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(AleraTokens.durationMid);
  });

  testWidgets('without a clarifier an error toast is shown as is', (
    tester,
  ) async {
    await _pumpHost(tester);

    AleraToast.publish(
      message: _original,
      tone: .error,
      duration: const Duration(milliseconds: 20),
    );
    await tester.pump();

    expect(find.text(_original), findsOneWidget);
    expect(find.text(_clarifying), findsNothing);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(AleraTokens.durationMid);
    expect(find.text(_original), findsNothing);
  });
}

List<String> _captureClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map<Object?, Object?>;
        copied.add(arguments['text']! as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

Future<void> _pumpHost(
  WidgetTester tester, {
  AleraToastErrorClarifier? clarifyError,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: AleraToastHost(
          clarifyError: clarifyError,
          clarifyingCaption: _clarifying,
          clarifiedCaption: _clarifiedCaption,
        ),
      ),
    ),
  );
}
