import 'package:alera/src/design_system/forms/alera_number_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client_models.dart';
import 'package:alera/src/features/workbench/presentation/terminal_pulse_dialog.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('saves the configured fixed wait and terminal input', (
    tester,
  ) async {
    final session = _PulseTerminalSessionHandle();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showTerminalPulseDialog(context, session),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Terminal Pulse'), findsOneWidget);
    expect(find.textContaining('fixed wait'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(AleraTextField),
        matching: find.byType(TextField),
      ),
      'reload',
    );
    await tester.tap(find.byType(Switch).at(0));
    await tester.tap(find.byType(Switch).at(1));
    await tester.enterText(
      find.descendant(
        of: find.byType(AleraNumberField),
        matching: find.byType(TextField),
      ),
      '2.5',
    );
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(session.savedArmed, isTrue);
    expect(
      session.savedConfiguration,
      const TerminalPulseConfiguration(
        command: 'reload',
        appendEnter: true,
        delayMilliseconds: 2500,
      ),
    );
    expect(find.text('Terminal Pulse'), findsNothing);
  });

  testWidgets('shows watcher failures without closing the terminal', (
    tester,
  ) async {
    final session = _PulseTerminalSessionHandle();
    await tester.pumpWidget(
      MaterialApp(home: TerminalPulseDialog(session: session)),
    );

    session.emitFailure('Terminal Pulse watcher stopped: unavailable');
    await tester.pump();

    expect(
      find.text('Terminal Pulse watcher stopped: unavailable'),
      findsOneWidget,
    );
    expect(find.text('Terminal host unavailable'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);

    session.emitState(
      const TerminalPulseState(
        configuration: TerminalPulseConfiguration(
          command: 'R',
          appendEnter: false,
          delayMilliseconds: 1500,
        ),
        armed: false,
      ),
    );
    await tester.pump();
    expect(
      find.text('Terminal Pulse watcher stopped: unavailable'),
      findsNothing,
    );
  });

  testWidgets('preserves an exact millisecond delay when saving', (
    tester,
  ) async {
    final session = _PulseTerminalSessionHandle(
      initialState: const TerminalPulseState(
        configuration: TerminalPulseConfiguration(
          command: 'r',
          appendEnter: true,
          delayMilliseconds: 125,
        ),
        armed: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: TerminalPulseDialog(session: session)),
    );

    final delayField = find.descendant(
      of: find.byType(AleraNumberField),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(delayField).controller?.text, '0.125');

    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(session.savedConfiguration?.delayMilliseconds, 125);
  });

  testWidgets('saves millisecond precision after editing the delay', (
    tester,
  ) async {
    final session = _PulseTerminalSessionHandle();
    await tester.pumpWidget(
      MaterialApp(home: TerminalPulseDialog(session: session)),
    );
    final delayField = find.descendant(
      of: find.byType(AleraNumberField),
      matching: find.byType(TextField),
    );

    await tester.enterText(delayField, '0.126');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();
    expect(tester.widget<TextField>(delayField).controller?.text, '0.126');
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(session.savedConfiguration?.delayMilliseconds, 126);
  });

  testWidgets('applies an external disarm while preserving edited input', (
    tester,
  ) async {
    final session = _PulseTerminalSessionHandle(
      initialState: const TerminalPulseState(
        configuration: TerminalPulseConfiguration(
          command: 'R',
          appendEnter: false,
          delayMilliseconds: 1500,
        ),
        armed: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: TerminalPulseDialog(session: session)),
    );
    final commandField = find.descendant(
      of: find.byType(AleraTextField),
      matching: find.byType(TextField),
    );
    await tester.enterText(commandField, 'local draft');

    session.emitState(
      const TerminalPulseState(
        configuration: TerminalPulseConfiguration(
          command: 'external',
          appendEnter: true,
          delayMilliseconds: 3000,
        ),
        armed: false,
      ),
    );
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(
      tester.widget<TextField>(commandField).controller?.text,
      'local draft',
    );
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);
  });
}

class _PulseTerminalSessionHandle({TerminalPulseState? initialState})
    extends TerminalSessionHandle {
  this
    : _pulse = ValueNotifier<TerminalPulseState>(
        initialState ??
            const TerminalPulseState(
              configuration: TerminalPulseConfiguration(
                command: 'R',
                appendEnter: false,
                delayMilliseconds: 1500,
              ),
              armed: false,
            ),
      );

  final ValueNotifier<String> _title = ValueNotifier<String>('Terminal');
  final ValueNotifier<TerminalPulseState> _pulse;

  TerminalPulseConfiguration? savedConfiguration;
  bool? savedArmed;

  void emitFailure(String error) {
    _pulse.value = TerminalPulseState(
      configuration: _pulse.value.configuration,
      armed: false,
      error: error,
    );
  }

  void emitState(TerminalPulseState state) {
    _pulse.value = state;
  }

  @override
  String get tabId => 'tab-1';

  @override
  String get workspaceId => 'workspace-1';

  @override
  String get displayTitle => 'Terminal';

  @override
  ValueListenable<String> get titleListenable => _title;

  @override
  bool get isRunning => true;

  @override
  bool get isStarting => false;

  @override
  bool get supportsTerminalPulse => true;

  @override
  ValueListenable<TerminalPulseState> get terminalPulseState => _pulse;

  @override
  String? get errorMessage => null;

  @override
  Future<void> configureTerminalPulse({
    required TerminalPulseConfiguration configuration,
    required bool armed,
  }) async {
    savedConfiguration = configuration;
    savedArmed = armed;
    _pulse.value = TerminalPulseState(
      configuration: configuration,
      armed: armed,
    );
  }

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<void> restart() async {}

  @override
  TerminalVisibilityLease acquireVisibility() =>
      const NoopTerminalVisibilityLease();

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) => const SizedBox.shrink();

  @override
  void requestFocus() {}
}
