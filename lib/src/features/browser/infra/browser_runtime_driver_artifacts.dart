part of 'browser_runtime_driver.dart';

bool _isBrowserArtifactMethod(String method) =>
    method == 'browser.screenshot' || method == 'browser.pdf';

Future<void> _removeBrowserArtifact(Object? value) async {
  if (value is! String || value.isEmpty) {
    return;
  }
  try {
    final file = File(value);
    if (await file.exists()) {
      await file.delete();
    }
  } on Object {
    // The host artifact sweeper remains the fallback for failed cleanup.
  }
}
