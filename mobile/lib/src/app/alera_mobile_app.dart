import 'package:alera_mobile/src/app/app_navigation.dart';
import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/features/hosts/presentation/host_list_screen.dart';
import 'package:alera_mobile/src/features/push_notifications/application/pending_push_intent_controller.dart';
import 'package:alera_mobile/src/features/push_notifications/application/push_coordinator.dart';
import 'package:alera_mobile/src/features/push_notifications/presentation/push_intent_router.dart';
import 'package:alera_mobile/src/features/updater/presentation/mobile_update_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AleraMobileApp extends ConsumerWidget {
  const AleraMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(pushCoordinatorProvider);
    ref.listen(pendingPushIntentControllerProvider, (previous, next) {
      if (next == null) {
        return;
      }
      ref.read(pendingPushIntentControllerProvider.notifier).clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        routePushIntent(ref, next);
      });
    });
    return MaterialApp(
      navigatorKey: aleraNavigatorKey,
      title: 'Alera',
      debugShowCheckedModeBanner: false,
      theme: buildAleraMobileDarkTheme(),
      // Wrapping the first route rather than `builder`, which mounts above the
      // Navigator and leaves the prompt without one to push a dialog onto.
      home: const MobileUpdatePrompt(child: HostListScreen()),
    );
  }
}
