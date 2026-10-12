import 'package:alera/src/design_system/forms/alera_duration_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  );
}

class const _Host({
  super.key,
  required final int initial,
  required final List<int> emitted,
  final String? Function(int seconds)? validate,
}) extends StatefulWidget {
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int _seconds = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AleraDurationField(
      labelText: 'Timeout',
      seconds: _seconds,
      errorText: widget.validate?.call(_seconds),
      onChanged: (value) {
        widget.emitted.add(value);
        setState(() => _seconds = value);
      },
    );
  }
}

String _number(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  testWidgets('shows the value in the largest unit that divides it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const _Host(key: ValueKey<int>(1), initial: 7200, emitted: <int>[]),
      ),
    );
    expect(_number(tester), '2');
    expect(find.text('Hours'), findsOneWidget);

    await tester.pumpWidget(
      _wrap(const _Host(key: ValueKey<int>(2), initial: 90, emitted: <int>[])),
    );
    expect(_number(tester), '90');
    expect(find.text('Seconds'), findsOneWidget);
  });

  testWidgets('editing the number reports seconds in the shown unit', (
    tester,
  ) async {
    final emitted = <int>[];
    await tester.pumpWidget(_wrap(_Host(initial: 900, emitted: emitted)));
    expect(find.text('Minutes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '45');
    await tester.pump();

    expect(emitted, <int>[2700]);
    expect(_number(tester), '45');
    expect(find.text('Minutes'), findsOneWidget);
  });

  testWidgets('changing the unit keeps the number and reports seconds', (
    tester,
  ) async {
    final emitted = <int>[];
    await tester.pumpWidget(_wrap(_Host(initial: 900, emitted: emitted)));

    await tester.tap(find.text('Minutes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hours').last);
    await tester.pumpAndSettle();

    expect(emitted, <int>[54000]);
    expect(_number(tester), '15');
    expect(find.text('Hours'), findsOneWidget);
  });

  testWidgets('out-of-range values are reported unclamped with caller error', (
    tester,
  ) async {
    final emitted = <int>[];
    await tester.pumpWidget(
      _wrap(
        _Host(
          initial: 60,
          emitted: emitted,
          validate: (seconds) => seconds > 3600 ? 'Use at most 1 hour.' : null,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '600');
    await tester.pump();

    expect(emitted, <int>[36000]);
    expect(_number(tester), '600');
    expect(find.text('Use at most 1 hour.'), findsOneWidget);
  });

  testWidgets('non-numeric input shows an error and reports nothing', (
    tester,
  ) async {
    final emitted = <int>[];
    await tester.pumpWidget(_wrap(_Host(initial: 60, emitted: emitted)));

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    expect(emitted, isEmpty);
    expect(find.text('Enter a number.'), findsOneWidget);
  });
}
