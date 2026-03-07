import 'package:url_launcher/url_launcher.dart';

/// Opens a local file with the system's default application.
///
/// Converts [path] to a `file:` URI and delegates to the OS via
/// `url_launcher`. Returns `true` if the file was opened successfully.
Future<bool> openFileNative(String path) async {
  final uri = Uri.file(path);
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri);
  }
  return false;
}
