import 'package:alera/src/core/build_flavor.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/app_menu/infra/native_app_menu_channel.dart';
import 'package:alera/src/features/app_menu/presentation/app_menu_actions.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_menu_test_support.dart';

void main() {
  group('app menu actions', () {
    testWidgets('openAppMenuSettings opens the settings dialog', (
      tester,
    ) async {
      await pumpActionHarness(
        tester,
        onPressed: (context, _) => openAppMenuSettings(context),
      );

      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Application'), findsWidgets);
    });

    testWidgets('checkForUpdatesFromAppMenu runs check and shows toast', (
      tester,
    ) async {
      final updateController = FakeUpdateController(
        AleraUpdateState(status: .idle, config: updateConfig()),
      );
      final toastMessages = <String>[];
      final sub = AleraToast.stream.listen((data) {
        toastMessages.add(data.message);
      });
      addTearDown(sub.cancel);

      await pumpActionHarness(
        tester,
        updateController: updateController,
        onPressed: (context, ref) => checkForUpdatesFromAppMenu(context, ref),
      );

      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump();

      expect(updateController.checkForUpdatesCalls, 1);
      expect(toastMessages, <String>['Alera is up to date.']);
    });

    testWidgets('showAppMenuAbout opens the about dialog', (tester) async {
      await pumpActionHarness(
        tester,
        onPressed: (context, ref) => showAppMenuAbout(
          context,
          ref,
          loadPackageInfo: () async => PackageInfo(
            appName: kAleraAppName,
            packageName: 'dev.leynier.alera',
            version: '1.2.3',
            buildNumber: '45',
          ),
        ),
      );

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();

      expect(find.text(kAleraAppName), findsWidgets);
      expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Check For Updates'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('about dialog copies the version to the clipboard', (
      tester,
    ) async {
      mockClipboard();
      final toastMessages = <String>[];
      final sub = AleraToast.stream.listen((data) {
        toastMessages.add(data.message);
      });
      addTearDown(sub.cancel);

      await pumpActionHarness(
        tester,
        onPressed: (context, ref) => showAppMenuAbout(
          context,
          ref,
          loadPackageInfo: () async => PackageInfo(
            appName: kAleraAppName,
            packageName: 'dev.leynier.alera',
            version: '1.2.3',
            buildNumber: '45',
          ),
        ),
      );

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Copy Version'));
      await tester.pumpAndSettle();

      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboard?.text, '1.2.3 (45)');
      expect(toastMessages, <String>['Version copied']);
    });

    testWidgets('about dialog runs the update check and closes', (
      tester,
    ) async {
      final updateController = FakeUpdateController(
        AleraUpdateState(status: .idle, config: updateConfig()),
      );
      final toastMessages = <String>[];
      final sub = AleraToast.stream.listen((data) {
        toastMessages.add(data.message);
      });
      addTearDown(sub.cancel);

      await pumpActionHarness(
        tester,
        updateController: updateController,
        onPressed: (context, ref) => showAppMenuAbout(
          context,
          ref,
          loadPackageInfo: () async => PackageInfo(
            appName: kAleraAppName,
            packageName: 'dev.leynier.alera',
            version: '1.2.3',
            buildNumber: '45',
          ),
        ),
      );

      await tester.tap(find.text('Run'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check For Updates'));
      await tester.pumpAndSettle();

      expect(find.text('Check For Updates'), findsNothing);
      expect(updateController.checkForUpdatesCalls, 1);
      expect(toastMessages, <String>['Alera is up to date.']);
    });

    testWidgets('exitAppFromMenu quits the app window', (tester) async {
      final window = FakeAppWindowController();
      await pumpActionHarness(
        tester,
        window: window,
        onPressed: (_, ref) => exitAppFromMenu(ref),
      );

      await tester.tap(find.text('Run'));
      await tester.pump();
      await tester.pump();

      expect(window.destroyCalls, 1);
    });
  });

  group('AleraAppMenuScope', () {
    for (final platform in <TargetPlatform>[
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      group('on $platform (native bridge compatibility)', () {
        testWidgets('renders no in-window menu bar', (tester) async {
          await withPlatform(platform, () async {
            await pumpMenuScope(tester);

            expect(find.byType(MenuBar), findsNothing);
            expect(find.byType(PlatformMenuBar), findsNothing);
          });
        });

        testWidgets('native channel opens the settings dialog', (tester) async {
          await withPlatform(platform, () async {
            await pumpMenuScope(tester);

            await invokeNativeMenuMethod(
              tester,
              NativeAppMenuMethod.openSettings,
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));

            expect(find.text('Application'), findsWidgets);
          });
        });

        testWidgets('native channel runs the update check', (tester) async {
          await withPlatform(platform, () async {
            final updateController = FakeUpdateController(
              AleraUpdateState(status: .idle, config: updateConfig()),
            );
            final toastMessages = <String>[];
            final sub = AleraToast.stream.listen((data) {
              toastMessages.add(data.message);
            });
            addTearDown(sub.cancel);

            await pumpMenuScope(tester, updateController: updateController);

            await invokeNativeMenuMethod(
              tester,
              NativeAppMenuMethod.checkForUpdates,
            );
            await tester.pump();
            await tester.pump();

            expect(updateController.checkForUpdatesCalls, 1);
            expect(toastMessages, <String>['Alera is up to date.']);
          });
        });

        testWidgets('native channel shows the about dialog', (tester) async {
          await withPlatform(platform, () async {
            mockPackageInfo(tester);

            await pumpMenuScope(tester);

            await invokeNativeMenuMethod(tester, NativeAppMenuMethod.showAbout);
            await tester.pumpAndSettle();

            expect(find.text(kAleraAppName), findsWidgets);
            expect(find.text('Version 1.2.3 (45)'), findsOneWidget);
          });
        });

        testWidgets('native channel quits the app window', (tester) async {
          await withPlatform(platform, () async {
            final window = FakeAppWindowController();
            await pumpMenuScope(tester, window: window);

            await invokeNativeMenuMethod(tester, NativeAppMenuMethod.exitApp);
            await tester.pump();
            await tester.pump();

            expect(window.destroyCalls, 1);
          });
        });

        testWidgets(
          'native channel edit methods act on the focused text field',
          (tester) async {
            await withPlatform(platform, () async {
              final controller = TextEditingController();
              addTearDown(controller.dispose);
              mockClipboard();
              await pumpMenuScope(
                tester,
                child: Scaffold(
                  body: Center(child: TextField(controller: controller)),
                ),
              );

              await tester.tap(find.byType(TextField));
              await tester.pump();
              await tester.enterText(find.byType(TextField), 'hello');
              await tester.pump();

              await invokeNativeMenuMethod(
                tester,
                NativeAppMenuMethod.selectAll,
              );
              await tester.pump();
              expect(
                controller.selection,
                const TextSelection(baseOffset: 0, extentOffset: 5),
              );

              await invokeNativeMenuMethod(tester, NativeAppMenuMethod.cut);
              await tester.pump();
              expect(controller.text, isEmpty);
              final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
              expect(clipboard?.text, 'hello');

              await invokeNativeMenuMethod(tester, NativeAppMenuMethod.paste);
              await tester.pump();
              expect(controller.text, 'hello');
            });
          },
        );
      });
    }

    testWidgets('uses PlatformMenuBar on macOS without in-window MenuBar', (
      tester,
    ) async {
      await withPlatform(.macOS, () async {
        await pumpMenuScope(tester);

        expect(find.byType(PlatformMenuBar), findsOneWidget);
        expect(find.byType(MenuBar), findsNothing);
      });
    });
  });
}
