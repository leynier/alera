import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/projects/presentation/add_project_dialog.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:path/path.dart' as p;

part 'add_project_dialog_local_test_cases.dart';
part 'add_project_dialog_clone_test_cases.dart';
part 'add_project_dialog_test_harness.dart';

void main() {
  _registerAddProjectDialogLocalTests();
  _registerAddProjectDialogCloneTests();
}
