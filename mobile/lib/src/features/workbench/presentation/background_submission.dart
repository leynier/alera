import 'package:alera_mobile/src/features/workbench/application/background_operations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Captures everything before removing the route; completion must never pop
/// whichever screen the user navigated to while the request was in flight.
/// Returns false for a duplicate so the caller can keep its draft editable.
bool submitInBackground(
  BuildContext context, {
  String? operationKey,
  required String title,
  required Future<String?> Function() action,
  WidgetBuilder? restoreForm,
  VoidCallback? Function()? prepareRestore,
  String Function()? successMessage,
  bool bottomSheet = true,
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
    onSuccess: () {
      if (messenger?.mounted == true) {
        messenger!.showSnackBar(
          SnackBar(
            content: Text(successMessage?.call() ?? '$title completed.'),
          ),
        );
      }
    },
    restore: restoreForm == null
        ? null
        : () {
            if (!navigator.mounted) return;
            final release = prepareRestore?.call();
            if (bottomSheet) {
              showModalBottomSheet<void>(
                context: navigator.context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: restoreForm,
              ).whenComplete(() => release?.call());
            } else {
              showDialog<void>(
                context: navigator.context,
                builder: restoreForm,
              ).whenComplete(() => release?.call());
            }
          },
  );
  if (!started) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('This operation is already running.')),
    );
    return false;
  }
  navigator.pop();
  return true;
}
