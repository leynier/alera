import 'package:integration_test/integration_test.dart';
import '../test/widget/alera_shell_page_test.dart' as shell;
import '../test/widget/browser_tab_visibility_test_cases.dart' as browser;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  shell.registerNativeRunBoardEditorLifecycleTest();
  browser.registerNativeBrowserVisibilityTest();
}
