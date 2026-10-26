import 'dart:async';

import 'package:alera_mobile/src/core/errors/action_failure_feedback.dart';
import 'package:flutter/material.dart';

/// Loads the next page and reports a failure instead of letting it escape.
class const LoadMoreButton({
  super.key,
  required final Future<void> Function() onLoad,
  final String label = 'Load More',
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => unawaited(_load(ScaffoldMessenger.of(context))),
      child: Text(label),
    ),
  );

  Future<void> _load(ScaffoldMessengerState messenger) async {
    try {
      await onLoad();
    } on Object catch (error, stackTrace) {
      showActionFailure(
        messenger,
        action: 'load more',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
