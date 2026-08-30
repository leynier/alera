import 'dart:ui';

import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:screen_retriever/screen_retriever.dart';

class ScreenRetrieverAppWindowDisplayProvider({ScreenRetriever? retriever})
    implements AppWindowDisplayProvider {
  this : _retriever = retriever ?? screenRetriever;

  final ScreenRetriever _retriever;

  @override
  Future<List<Rect>> visibleDisplayBounds() async {
    final displays = await _retriever.getAllDisplays();
    return <Rect>[
      for (final display in displays)
        Rect.fromLTWH(
          display.visiblePosition?.dx ?? 0,
          display.visiblePosition?.dy ?? 0,
          (display.visibleSize ?? display.size).width,
          (display.visibleSize ?? display.size).height,
        ),
    ];
  }
}
