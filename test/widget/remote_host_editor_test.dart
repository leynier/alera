import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('remote host save button uses the click cursor', (tester) async {
    final aliasController = TextEditingController();
    final hostController = TextEditingController();
    final portController = TextEditingController(text: '22');
    final usernameController = TextEditingController();
    final installDirController = TextEditingController();
    addTearDown(aliasController.dispose);
    addTearDown(hostController.dispose);
    addTearDown(portController.dispose);
    addTearDown(usernameController.dispose);
    addTearDown(installDirController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: RemoteHostEditor(
            aliasController: aliasController,
            hostController: hostController,
            portController: portController,
            usernameController: usernameController,
            installDirController: installDirController,
            platform: '',
            arch: '',
            authKind: .agent,
            hasSelection: false,
            saving: false,
            planning: false,
            bootstrapping: false,
            onPlatformChanged: (_) {},
            onArchChanged: (_) {},
            onAuthKindChanged: (_) {},
            onSave: () {},
            onRemove: null,
            onPlan: null,
            onBootstrap: null,
            onCancel: null,
          ),
        ),
      ),
    );

    final saveButton = find.widgetWithText(FilledButton, 'Save');
    await tester.ensureVisible(saveButton);
    await tester.pump();

    final mouse = await tester.createGesture(kind: .mouse, pointer: 1);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(saveButton));
    await tester.pump();

    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.click,
    );
  });
}
