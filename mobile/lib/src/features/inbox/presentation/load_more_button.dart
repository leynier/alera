import 'dart:async';

import 'package:flutter/material.dart';

/// Loads the next page and reports a failure instead of letting it escape.
class const LoadMoreButton({
  super.key,
  required final Future<void> Function() onLoad,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => unawaited(_load(ScaffoldMessenger.of(context))),
      child: const Text('Load More'),
    ),
  );

  Future<void> _load(ScaffoldMessengerState messenger) async {
    try {
      await onLoad();
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not load more: $error')),
      );
    }
  }
}
