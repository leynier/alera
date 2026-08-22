import 'package:alera_mobile/src/features/workbench/presentation/prompt_path_insertion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('inserts one path per line at the current selection', () {
    final controller = TextEditingController(text: 'Build this now');
    controller.selection = const TextSelection.collapsed(offset: 6);

    insertPromptPaths(controller, <String>['/host/one.png', '/host/two.jpg']);

    expect(controller.text, 'Build \n/host/one.png\n/host/two.jpg\nthis now');
    expect(
      controller.selection.baseOffset,
      controller.text.indexOf('\nthis now') + 1,
    );
  });

  test('falls back to the end and removes control characters', () {
    final controller = TextEditingController(text: 'Existing');
    controller.selection = const TextSelection.collapsed(offset: -1);

    insertPromptPaths(controller, <String>['/host/a\npath.png']);

    expect(controller.text, 'Existing\n/host/apath.png');
    expect(controller.selection.baseOffset, controller.text.length);
  });
}
