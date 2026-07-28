import 'dart:async';

import 'package:flutter/widgets.dart';

import 'browser_client.dart';

/// Flutter surface for a page owned by [AleraBrowserClient].
final class AleraBrowserView extends StatefulWidget {
  const AleraBrowserView({
    required this.client,
    required this.pageId,
    super.key,
  });

  final AleraBrowserClient client;
  final String pageId;

  @override
  State<AleraBrowserView> createState() => _AleraBrowserViewState();
}

final class _AleraBrowserViewState extends State<AleraBrowserView> {
  late final String _leaseId = 'widget:${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    unawaited(widget.client.attachPage(widget.pageId, leaseId: _leaseId));
  }

  @override
  void didUpdateWidget(covariant AleraBrowserView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client == widget.client &&
        oldWidget.pageId == widget.pageId) {
      return;
    }
    unawaited(oldWidget.client.detachPage(oldWidget.pageId, leaseId: _leaseId));
    unawaited(widget.client.attachPage(widget.pageId, leaseId: _leaseId));
  }

  @override
  void dispose() {
    unawaited(widget.client.detachPage(widget.pageId, leaseId: _leaseId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.client.buildPageView(widget.pageId);
}
