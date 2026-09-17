import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/workbench/application/background_operations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Captures everything before removing the route; completion must never pop
/// whichever screen the user navigated to while the request was in flight.
void submitInBackground(
  BuildContext context, {
  String? operationKey,
  required String title,
  required Future<String?> Function() action,
  WidgetBuilder? restoreForm,
  void Function()? prepareRestore,
  String Function()? successMessage,
  bool bottomSheet = false,
}) {
  final jobs = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(backgroundOperationsProvider.notifier);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final started = jobs.submit(
    operationKey: operationKey,
    title: title,
    action: action,
    onSuccess: () => AleraToast.publish(
      message: successMessage?.call() ?? '$title completed.',
      tone: .success,
    ),
    restore: restoreForm == null
        ? null
        : () {
            if (!navigator.mounted) return;
            prepareRestore?.call();
            if (bottomSheet) {
              showModalBottomSheet<void>(
                context: navigator.context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: restoreForm,
              );
            } else {
              showDialog<void>(
                context: navigator.context,
                builder: restoreForm,
              );
            }
          },
  );
  navigator.pop();
  if (!started) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('This operation is already running.')),
    );
  }
}
