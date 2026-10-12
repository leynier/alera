import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_action_result.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_form_values.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_address.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter/material.dart';

const String sshAddressHelperText =
    'Same address you give the ssh command. Port is optional.';
const String sshAuthenticationHelperText =
    'Alera uses your SSH agent and ~/.ssh/config. Password login is not supported.';

/// State of the identity form shared by Add Host and Edit Connection. The
/// alias follows the host typed into SSH Address until the user edits it.
class RemoteHostConnectionFormController extends ChangeNotifier {
  RemoteHostConnectionFormController({RemoteHostConnectionValues? initial})
    : alias = TextEditingController(text: initial?.alias ?? ''),
      address = TextEditingController(text: initial?.address ?? ''),
      identityFile = TextEditingController(text: initial?.identityFile ?? ''),
      _authKind = initial?.authKind == SshAuthKind.key
          ? SshAuthKind.key
          : SshAuthKind.agent,
      _aliasTouched = (initial?.alias ?? '').isNotEmpty,
      passwordAuth = initial?.authKind == SshAuthKind.password;

  final TextEditingController alias;
  final TextEditingController address;
  final TextEditingController identityFile;

  /// The host was saved with password login, which Alera no longer offers.
  final bool passwordAuth;
  SshAuthKind _authKind;
  bool _aliasTouched;
  String? _error;

  SshAuthKind get authKind => _authKind;

  String? get error => _error;

  set error(String? value) {
    if (value != _error) {
      _error = value;
      notifyListeners();
    }
  }

  set authKind(SshAuthKind value) {
    if (value != _authKind) {
      _authKind = value;
      notifyListeners();
    }
  }

  RemoteHostConnectionValues get values => RemoteHostConnectionValues(
    alias: alias.text,
    address: address.text,
    authKind: _authKind,
    identityFile: identityFile.text,
  );

  void addressChanged(String text) {
    if (!_aliasTouched) {
      alias.text = tryParseSshAddress(text)?.host ?? '';
    }
    error = null;
  }

  void aliasChanged(String text) {
    _aliasTouched = text.isNotEmpty;
    error = null;
  }

  @override
  void dispose() {
    alias.dispose();
    address.dispose();
    identityFile.dispose();
    super.dispose();
  }
}

/// Alias, SSH Address, Authentication and, with a key file, Identity File.
class const RemoteHostConnectionForm({
  super.key,
  required final RemoteHostConnectionFormController controller,
  final bool identityFileSupported = false,
  final bool enabled = true,
  final bool autofocus = false,
  final ValueChanged<String>? onSubmitted,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final helperStyle = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraTextField(
            controller: controller.address,
            labelText: 'SSH Address',
            hintText: 'user@host',
            prefixIcon: AleraIcons.public,
            autofocus: autofocus,
            enabled: enabled,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: controller.addressChanged,
            onSubmitted: onSubmitted,
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(sshAddressHelperText, style: helperStyle),
          const SizedBox(height: AleraTokens.space12),
          AleraTextField(
            controller: controller.alias,
            labelText: 'Alias',
            hintText: 'Build Mac',
            prefixIcon: AleraIcons.tag,
            enabled: enabled,
            onChanged: controller.aliasChanged,
            onSubmitted: onSubmitted,
          ),
          const SizedBox(height: AleraTokens.space16),
          Text(
            'Authentication',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AleraSegmentedButton<SshAuthKind>(
              segments: const <ButtonSegment<SshAuthKind>>[
                ButtonSegment<SshAuthKind>(
                  value: SshAuthKind.agent,
                  label: Text('SSH Agent'),
                ),
                ButtonSegment<SshAuthKind>(
                  value: SshAuthKind.key,
                  label: Text('Key File'),
                ),
              ],
              selected: controller.authKind,
              onSelectionChanged: (value) {
                if (enabled) {
                  controller.authKind = value;
                }
              },
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(sshAuthenticationHelperText, style: helperStyle),
          if (controller.authKind == SshAuthKind.key &&
              identityFileSupported) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: controller.identityFile,
              labelText: 'Identity File',
              hintText: '~/.ssh/id_ed25519',
              prefixIcon: AleraIcons.secure,
              enabled: enabled,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: onSubmitted,
            ),
          ],
          if (controller.passwordAuth) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            const AleraInlineNotice(
              message: remoteHostPasswordUnsupportedMessage,
              tone: .warning,
            ),
          ],
          if (controller.error case final error?) ...<Widget>[
            const SizedBox(height: AleraTokens.space12),
            AleraInlineNotice(message: error, tone: .error),
          ],
        ],
      ),
    );
  }
}
