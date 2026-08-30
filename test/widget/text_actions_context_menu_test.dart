import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/menus/alera_text_selection_toolbar.dart';
import 'package:alera/src/features/pull_requests/presentation/pull_request_link_form.dart';
import 'package:alera/src/features/text_actions/application/text_action_replacement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('adds Text Actions after the native editing commands', (
    tester,
  ) async {
    var opened = false;
    final controller = TextEditingController(text: 'Translate this text')
      ..selection = const TextSelection(baseOffset: 0, extentOffset: 9);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraTextActionsScope(
            enabled: true,
            onOpen: (_, _, _) => opened = true,
            child: TextField(
              controller: controller,
              contextMenuBuilder: AleraTextActionsScope.buildContextMenu,
            ),
          ),
        ),
      ),
    );

    final editableFinder = find.byType(EditableText);
    final editable = tester.state<EditableTextState>(editableFinder);
    final nativeItems = editable.contextMenuButtonItems;
    final toolbar = AleraTextActionsScope.buildContextMenu(
      tester.element(editableFinder),
      editable,
    ) as AleraTextSelectionToolbar;
    final items = toolbar.buttonItems;

    expect(
      items.take(nativeItems.length).map((item) => item.type),
      nativeItems.map((item) => item.type),
    );
    expect(items.last.label, 'Text Actions');
    items.last.onPressed!();
    expect(opened, isTrue);
  });

  testWidgets('hides Text Actions for ineligible fields and selections', (
    tester,
  ) async {
    Future<List<ContextMenuButtonItem>> menuItems({
      bool scopeEnabled = true,
      bool readOnly = false,
      bool obscureText = false,
      TextInputType? keyboardType,
      bool textActionsEnabled = true,
      TextSelection selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      ),
    }) async {
      final controller = TextEditingController(text: 'text value')
        ..selection = selection;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AleraTextActionsScope(
              enabled: scopeEnabled,
              onOpen: (_, _, _) {},
              child: TextField(
                controller: controller,
                readOnly: readOnly,
                obscureText: obscureText,
                keyboardType: keyboardType,
                contextMenuBuilder: (context, editable) {
                  return AleraTextActionsScope.buildContextMenu(
                    context,
                    editable,
                    textActionsEnabled: textActionsEnabled,
                  );
                },
              ),
            ),
          ),
        ),
      );
      final finder = find.byType(EditableText);
      final editable = tester.state<EditableTextState>(finder);
      final toolbar = AleraTextActionsScope.buildContextMenu(
        tester.element(finder),
        editable,
        textActionsEnabled: textActionsEnabled,
      ) as AleraTextSelectionToolbar;
      return toolbar.buttonItems;
    }

    bool hasTextActions(List<ContextMenuButtonItem> items) =>
        items.any((item) => item.label == 'Text Actions');

    expect(hasTextActions(await menuItems(scopeEnabled: false)), isFalse);
    expect(hasTextActions(await menuItems(readOnly: true)), isFalse);
    expect(hasTextActions(await menuItems(obscureText: true)), isFalse);
    expect(hasTextActions(await menuItems(keyboardType: .number)), isFalse);
    expect(hasTextActions(await menuItems(textActionsEnabled: false)), isFalse);
    expect(
      hasTextActions(await menuItems(selection: const .collapsed(offset: 2))),
      isFalse,
    );
  });

  testWidgets('preserves AleraTextField paste interception', (tester) async {
    var pasteCalls = 0;
    final controller = TextEditingController(text: 'selected')
      ..selection = const TextSelection(baseOffset: 0, extentOffset: 8);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraTextActionsScope(
            enabled: true,
            onOpen: (_, _, _) {},
            child: AleraTextField(
              controller: controller,
              onPaste: () async {
                pasteCalls += 1;
                return true;
              },
            ),
          ),
        ),
      ),
    );

    final editableFinder = find.byType(EditableText);
    final editable = tester.state<EditableTextState>(editableFinder);
    final field = tester.widget<TextField>(find.byType(TextField));
    final toolbar = field.contextMenuBuilder!(
      tester.element(editableFinder),
      editable,
    ) as AleraTextSelectionToolbar;
    final paste = toolbar.buttonItems.firstWhere(
      (item) => item.type == ContextMenuButtonType.paste,
    );

    paste.onPressed!();
    await tester.pump();
    expect(pasteCalls, 1);
    expect(controller.text, 'selected');
  });

  testWidgets('Pull Request fields expose the shared Text Actions menu', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'pull request text')
      ..selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraTextActionsScope(
            enabled: true,
            onOpen: (_, _, _) {},
            child: PullRequestLinkForm(
              controller: controller,
              busy: false,
              suggestedReview: null,
              onChanged: () {},
              onSubmitted: () {},
            ),
          ),
        ),
      ),
    );

    final editableFinder = find.byType(EditableText);
    final editable = tester.state<EditableTextState>(editableFinder);
    final field = tester.widget<TextField>(find.byType(TextField));
    final toolbar = field.contextMenuBuilder!(
      tester.element(editableFinder),
      editable,
    ) as AleraTextSelectionToolbar;

    expect(
      toolbar.buttonItems.any((item) => item.label == 'Text Actions'),
      isTrue,
    );
  });

  testWidgets('replacement is undoable and redoable', (tester) async {
    final controller = TextEditingController(text: 'Before old after')
      ..selection = const TextSelection(baseOffset: 7, extentOffset: 10);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    final editableFinder = find.byType(EditableText);
    final editable = tester.state<EditableTextState>(editableFinder);
    editable.widget.focusNode.requestFocus();
    await tester.pump(const Duration(milliseconds: 600));
    final captured = editable.textEditingValue;
    final editingContext = editable.widget.focusNode.context!;

    Actions.invoke(
      editingContext,
      buildTextActionReplacementIntent(
        captured: captured,
        replacement: 'new words',
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.text, 'Before new words after');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 7, extentOffset: 16),
    );

    Actions.invoke(editingContext, const UndoTextIntent(.keyboard));
    await tester.pump();
    expect(controller.text, 'Before old after');

    Actions.invoke(editingContext, const RedoTextIntent(.keyboard));
    await tester.pump();
    expect(controller.text, 'Before new words after');
  });
}
