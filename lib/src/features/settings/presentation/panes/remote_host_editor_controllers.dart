import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter/widgets.dart';

/// The text controllers behind [RemoteHostEditor], seeded from a target and
/// reset together so the pane cannot forget one of them.
class RemoteHostEditorControllers {
  final TextEditingController alias = TextEditingController();
  final TextEditingController host = TextEditingController();
  final TextEditingController port = TextEditingController(text: _defaultPort);
  final TextEditingController username = TextEditingController();
  final TextEditingController installDir = TextEditingController();
  final TextEditingController projectsDir = TextEditingController();

  static const String _defaultPort = '22';

  void seed(SshTarget target) {
    alias.text = target.alias;
    host.text = target.host;
    port.text = target.port.toString();
    username.text = target.username;
    installDir.text = target.installDir ?? '';
    projectsDir.text = target.projectsDir ?? '';
  }

  void clear() {
    alias.clear();
    host.clear();
    port.text = _defaultPort;
    username.clear();
    installDir.clear();
    projectsDir.clear();
  }

  void dispose() {
    alias.dispose();
    host.dispose();
    port.dispose();
    username.dispose();
    installDir.dispose();
    projectsDir.dispose();
  }
}
