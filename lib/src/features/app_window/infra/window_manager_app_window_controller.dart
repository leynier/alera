import 'dart:ui';

import 'package:alera/src/features/app_window/application/app_window_controller.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagerAppWindowController implements AppWindowController {
  WindowManagerAppWindowController({WindowManager? manager})
    : _manager = manager ?? windowManager;

  final WindowManager _manager;
  final Map<AppWindowEventListener, WindowListener> _listeners =
      <AppWindowEventListener, WindowListener>{};

  @override
  void addListener(AppWindowEventListener listener) {
    final adapter = _WindowManagerListenerAdapter(listener);
    _listeners[listener] = adapter;
    _manager.addListener(adapter);
  }

  @override
  void removeListener(AppWindowEventListener listener) {
    final adapter = _listeners.remove(listener);
    if (adapter != null) {
      _manager.removeListener(adapter);
    }
  }

  @override
  Future<Rect> getBounds() => _manager.getBounds();

  @override
  Future<bool> isFullScreen() => _manager.isFullScreen();

  @override
  Future<bool> isMaximized() => _manager.isMaximized();

  @override
  Future<bool> isMinimized() => _manager.isMinimized();

  @override
  Future<void> hide() async {
    await _manager.hide();
    // window_manager 0.5.2 dispatches macOS orderOut asynchronously, so the
    // method channel can return while isVisible is still true.
    await _waitUntilHidden();
  }

  Future<void> _waitUntilHidden() async {
    final deadline = DateTime.now().add(const Duration(milliseconds: 500));
    while (await _manager.isVisible()) {
      if (DateTime.now().isAfter(deadline)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  @override
  Future<void> show() => _manager.show();

  @override
  Future<void> restore() => _manager.restore();

  @override
  Future<void> focus() => _manager.focus();

  @override
  Future<bool> isVisible() => _manager.isVisible();

  @override
  Future<void> maximize() => _manager.maximize();

  @override
  Future<void> setBounds(Rect bounds) => _manager.setBounds(bounds);

  @override
  Future<void> setFullScreen(bool value) => _manager.setFullScreen(value);

  @override
  Future<void> setPreventClose(bool value) => _manager.setPreventClose(value);

  @override
  Future<void> setTitle(String title) => _manager.setTitle(title);

  @override
  Future<void> close() => _manager.close();

  @override
  Future<void> destroy() => _manager.destroy();
}

class _WindowManagerListenerAdapter with WindowListener {
  _WindowManagerListenerAdapter(this._delegate);

  final AppWindowEventListener _delegate;

  @override
  void onWindowClose() => _delegate.onWindowClose();

  @override
  void onWindowMaximize() => _delegate.onWindowMaximize();

  @override
  void onWindowUnmaximize() => _delegate.onWindowUnmaximize();

  @override
  void onWindowMinimize() => _delegate.onWindowMinimize();

  @override
  void onWindowRestore() => _delegate.onWindowRestore();

  @override
  void onWindowResize() => _delegate.onWindowResize();

  @override
  void onWindowResized() => _delegate.onWindowResized();

  @override
  void onWindowMove() => _delegate.onWindowMove();

  @override
  void onWindowMoved() => _delegate.onWindowMoved();

  @override
  void onWindowEnterFullScreen() => _delegate.onWindowEnterFullScreen();

  @override
  void onWindowLeaveFullScreen() => _delegate.onWindowLeaveFullScreen();
}
