import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:alera/src/features/agent_profiles/domain/managed_agent_profile_options.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profile_managed_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const models = <ManagedAgentOption>[
    ManagedAgentOption('grok-4.7-high', 'Grok 4.7 High'),
    ManagedAgentOption('grok-4.7-xhigh', 'Grok 4.7 Extra High'),
    ManagedAgentOption('grok-4.7-xhigh-fast', 'Grok 4.7 Extra High Fast'),
    ManagedAgentOption('claude-fable-5-1-medium', 'Claude Fable 5.1 Medium'),
    ManagedAgentOption('claude-fable-5-1-high', 'Claude Fable 5.1 High'),
    ManagedAgentOption(
      'claude-fable-5-1-thinking-high',
      'Claude Fable 5.1 Thinking High',
    ),
    ManagedAgentOption('composer-2.5', 'Composer 2.5'),
    ManagedAgentOption('composer-2.5-fast', 'Composer 2.5 Fast'),
    ManagedAgentOption('auto', 'Auto'),
  ];

  testWidgets('Cursor family controls rewrite model to a published slug', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(
        key: key,
        adapter: AgentType.cursor,
        models: models,
        config: const <String, Object?>{'model': 'grok-4.7-xhigh'},
      ),
    );

    expect(find.text('Grok 4.7'), findsOneWidget);
    expect(find.text('Extra High'), findsOneWidget);
    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Fast'), findsOneWidget);
    expect(_checkbox(tester, 'Fast').value, isFalse);
    expect(_checkbox(tester, 'Fast').enabled, isTrue);
    expect(find.text('High'), findsNothing);

    await tester.tap(find.text('Extra High'));
    await tester.pumpAndSettle();
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Medium'), findsNothing);
    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();

    expect(key.currentState!.config['model'], 'grok-4.7-high');
    expect(find.text('Fast'), findsOneWidget);
    expect(_checkbox(tester, 'Fast').value, isFalse);
    expect(_checkbox(tester, 'Fast').enabled, isFalse);
    await _toggle(tester, 'Fast');
    expect(key.currentState!.config['model'], 'grok-4.7-high');

    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extra High').last);
    await tester.pumpAndSettle();
    expect(key.currentState!.config['model'], 'grok-4.7-xhigh');

    await _toggle(tester, 'Fast');
    expect(key.currentState!.config['model'], 'grok-4.7-xhigh-fast');
    expect(_checkbox(tester, 'Fast').value, isTrue);

    await tester.tap(find.text('Grok 4.7'));
    await tester.pump();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search Models',
      ),
      'Fable',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(AleraMenuItem, 'Claude Fable 5.1'));
    await tester.pumpAndSettle();

    expect(key.currentState!.config['model'], 'claude-fable-5-1-high');
    expect(find.text('Claude Fable 5.1'), findsOneWidget);
    expect(find.text('Thinking'), findsOneWidget);
    expect(find.text('Fast'), findsNothing);
    expect(_checkbox(tester, 'Thinking').value, isFalse);

    await tester.tap(find.text('High'));
    await tester.pumpAndSettle();
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Extra High'), findsNothing);
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();

    await _toggle(tester, 'Thinking');
    expect(key.currentState!.config['model'], 'claude-fable-5-1-thinking-high');
    expect(_checkbox(tester, 'Thinking').value, isTrue);
    expect(find.text('Fast'), findsNothing);
  });

  testWidgets('an unknown Cursor model id keeps the raw value', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(
        key: key,
        adapter: AgentType.cursor,
        models: models,
        config: const <String, Object?>{'model': 'not-a-real-model'},
      ),
    );

    expect(find.text('Custom: not-a-real-model'), findsOneWidget);
    expect(find.text('Effort'), findsNothing);
    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Fast'), findsNothing);
    expect(key.currentState!.config['model'], 'not-a-real-model');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'not-a-real-model',
    );
  });

  testWidgets('other adapters keep the flat model list', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _Harness(
        adapter: AgentType.codex,
        models: models,
        config: const <String, Object?>{'model': 'grok-4.7-xhigh'},
      ),
    );

    expect(find.text('Grok 4.7 Extra High'), findsOneWidget);
    expect(find.text('Effort'), findsNothing);
    expect(find.text('Thinking'), findsNothing);
    expect(find.text('Fast'), findsNothing);
    expect(find.text('Reasoning Effort'), findsOneWidget);
  });
}

AleraCheckbox _checkbox(WidgetTester tester, String title) {
  return tester.widget<AleraCheckbox>(
    find.descendant(
      of: find.ancestor(
        of: find.text(title),
        matching: find.byType(AleraSettingRow),
      ),
      matching: find.byType(AleraCheckbox),
    ),
  );
}

Future<void> _toggle(WidgetTester tester, String title) async {
  final checkbox = find.descendant(
    of: find.ancestor(
      of: find.text(title),
      matching: find.byType(AleraSettingRow),
    ),
    matching: find.byType(AleraCheckbox),
  );
  await tester.ensureVisible(checkbox);
  await tester.tap(checkbox);
  await tester.pumpAndSettle();
}

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.adapter,
    required this.models,
    required this.config,
  });

  final AgentType adapter;
  final List<ManagedAgentOption> models;
  final Map<String, Object?> config;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late Map<String, Object?> config = Map<String, Object?>.of(widget.config);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 1100,
            child: AgentProfileManagedEditor(
              adapter: widget.adapter,
              config: config,
              models: widget.models,
              personas: const <ManagedAgentOption>[],
              enabled: true,
              onChanged: (value) => setState(() => config = value),
              onRefreshModels: null,
              onRefreshPersonas: null,
            ),
          ),
        ),
      ),
    );
  }
}
