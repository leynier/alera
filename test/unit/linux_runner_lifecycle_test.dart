import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Linux window destruction releases engine-bound services first', () {
    final source = File('linux/runner/my_application.cc').readAsStringSync();
    final handler = source.indexOf('static void on_window_destroy');
    final cleanup = source.indexOf('clear_window_services(self);', handler);
    final windowReset = source.indexOf('self->window = nullptr;', handler);

    expect(handler, isNonNegative);
    expect(cleanup, greaterThan(handler));
    expect(windowReset, greaterThan(cleanup));
  });

  test('Linux desktop presence accepts a missing method argument', () {
    final source = File('linux/runner/desktop_presence.cc').readAsStringSync();
    expect(
      source,
      contains(
        'if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP)',
      ),
    );
  });

  test('Linux fallback tray releases its GTK menu', () {
    final source = File(
      'linux/runner/appindicator_tray_fallback.cc',
    ).readAsStringSync();
    final cleanup = source.indexOf('void appindicator_tray_fallback_free');
    final destroy = source.indexOf('gtk_widget_destroy(tray->menu)', cleanup);
    final release = source.indexOf('g_clear_object(&tray->menu);', destroy);

    expect(cleanup, isNonNegative);
    expect(destroy, greaterThan(cleanup));
    expect(release, greaterThan(destroy));
  });
}
