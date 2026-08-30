import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workbench_sidebar_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('navigation controls are disabled without history', (
    tester,
  ) async {
    final controller = _ToolbarTestController();
    await _pumpToolbar(tester, controller);

    expect(_button(tester, 'Go Back').onPressed, isNull);
    expect(_button(tester, 'Go Forward').onPressed, isNull);
  });

  testWidgets('navigation controls dispatch the matching direction', (
    tester,
  ) async {
    final controller = _ToolbarTestController(
      canGoBackValue: true,
      canGoForwardValue: true,
    );
    await _pumpToolbar(tester, controller);

    await tester.tap(find.byTooltip('Go Back'));
    await tester.tap(find.byTooltip('Go Forward'));

    expect(controller.backCalls, 1);
    expect(controller.forwardCalls, 1);
  });
}

Future<void> _pumpToolbar(
  WidgetTester tester,
  _ToolbarTestController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [workbenchControllerProvider.overrideWith(() => controller)],
      child: const MaterialApp(
        home: Scaffold(body: WorkbenchSidebarToolbar(onAddWorkspace: _noop)),
      ),
    ),
  );
  await tester.pump();
}

IconButton _button(WidgetTester tester, String tooltip) {
  final button = find.ancestor(
    of: find.byTooltip(tooltip),
    matching: find.byType(IconButton),
  );
  return tester.widget<IconButton>(button);
}

void _noop() {}

class _ToolbarTestController({
  final bool canGoBackValue = false,
  final bool canGoForwardValue = false,
}) extends WorkbenchController {
  int backCalls = 0;
  int forwardCalls = 0;

  @override
  WorkbenchState build() => const WorkbenchState();

  @override
  bool get canGoBack => canGoBackValue;

  @override
  bool get canGoForward => canGoForwardValue;

  @override
  Future<void> goBack() async {
    backCalls += 1;
  }

  @override
  Future<void> goForward() async {
    forwardCalls += 1;
  }
}
