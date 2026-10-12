import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_action_result.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_form_values.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter/material.dart';

const String projectsFolderHelpText =
    'Where projects are cloned on this host when no path is chosen. Empty means alera-projects under the home folder. ~ and %VAR% are expanded on the host.';

/// Unsaved Advanced values of one host. The pane owns it so it can ask
/// whether to save before the user leaves the host.
class RemoteHostAdvancedDraft extends ChangeNotifier {
  RemoteHostAdvancedDraft(SshTarget target)
    : hostId = target.id,
      _baseline = RemoteHostAdvancedValues.fromTarget(target) {
    _seed(_baseline);
    for (final controller in <TextEditingController>[
      installDir,
      projectsDir,
      identityFile,
    ]) {
      controller.addListener(notifyListeners);
    }
  }

  final String hostId;
  final TextEditingController installDir = TextEditingController();
  final TextEditingController projectsDir = TextEditingController();
  final TextEditingController identityFile = TextEditingController();
  RemoteHostAdvancedValues _baseline;
  String _platform = '';
  String _arch = '';

  String get platform => _platform;

  String get arch => _arch;

  set platform(String value) {
    _platform = value;
    notifyListeners();
  }

  set arch(String value) {
    _arch = value;
    notifyListeners();
  }

  /// Whether the host takes an identity file here, which only key file
  /// login does.
  bool get hasIdentityFile => _baseline.identityFile != null;

  RemoteHostAdvancedValues get values => RemoteHostAdvancedValues(
    installDir: installDir.text,
    projectsDir: projectsDir.text,
    platform: _platform,
    arch: _arch,
    identityFile: hasIdentityFile ? identityFile.text : null,
  );

  bool get isDirty => !values.sameAs(_baseline);

  /// Follows a change made elsewhere (another window, the CLI, a save) while
  /// nothing is being edited here.
  void syncFrom(SshTarget target) {
    final next = RemoteHostAdvancedValues.fromTarget(target);
    if (next.sameAs(_baseline) &&
        (next.identityFile == null) == (_baseline.identityFile == null)) {
      return;
    }
    if (isDirty) {
      _baseline = next;
      notifyListeners();
      return;
    }
    _baseline = next;
    _seed(next);
    notifyListeners();
  }

  void revert() {
    _seed(_baseline);
    notifyListeners();
  }

  void _seed(RemoteHostAdvancedValues values) {
    if (installDir.text != values.installDir) {
      installDir.text = values.installDir;
    }
    if (projectsDir.text != values.projectsDir) {
      projectsDir.text = values.projectsDir;
    }
    if (identityFile.text != (values.identityFile ?? '')) {
      identityFile.text = values.identityFile ?? '';
    }
    _platform = values.platform;
    _arch = values.arch;
  }

  @override
  void dispose() {
    installDir.dispose();
    projectsDir.dispose();
    identityFile.dispose();
    super.dispose();
  }
}

/// Where the runtime goes and what it is built for, with explicit Revert and
/// Save. Locked while the runtime installs. The owner of [draft] keeps it in
/// step with the stored target.
class const RemoteHostAdvancedGroup({
  super.key,
  required final RemoteHostAdvancedDraft draft,
  required final bool locked,
  required final bool saving,
  required final bool identityFileSupported,
  required final VoidCallback onSave,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = !locked && !saving;
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final dirty = draft.isDirty;
        return AleraSettingsGroup(
          title: 'Advanced',
          description:
              'Where the Alera runtime is installed and what it is built for.',
          collapsible: true,
          initiallyExpanded: dirty,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space12),
              child: Column(
                crossAxisAlignment: .stretch,
                children: <Widget>[
                  if (locked) ...<Widget>[
                    const AleraInlineNotice(
                      message: remoteHostInstallLockedMessage,
                    ),
                    const SizedBox(height: AleraTokens.space12),
                  ],
                  AleraTextField(
                    controller: draft.installDir,
                    labelText: 'Install Directory',
                    hintText: 'Default per platform',
                    prefixIcon: AleraIcons.folder,
                    enabled: enabled,
                  ),
                  const SizedBox(height: AleraTokens.space12),
                  AleraTextField(
                    controller: draft.projectsDir,
                    labelText: 'Projects Folder',
                    hintText: 'alera-projects under the home folder',
                    prefixIcon: AleraIcons.folder,
                    enabled: enabled,
                  ),
                  const SizedBox(height: AleraTokens.space4),
                  Text(
                    projectsFolderHelpText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                  const SizedBox(height: AleraTokens.space12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: AleraDropdownField<String>(
                          key: ValueKey<String>('Platform:${draft.platform}'),
                          labelText: 'Platform',
                          value: draft.platform,
                          enabled: enabled,
                          entries: _platformEntries,
                          onChanged: (value) => draft.platform = value,
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space12),
                      Expanded(
                        child: AleraDropdownField<String>(
                          key: ValueKey<String>('Architecture:${draft.arch}'),
                          labelText: 'Architecture',
                          value: draft.arch,
                          enabled: enabled,
                          entries: _archEntries,
                          onChanged: (value) => draft.arch = value,
                        ),
                      ),
                    ],
                  ),
                  if (draft.hasIdentityFile &&
                      identityFileSupported) ...<Widget>[
                    const SizedBox(height: AleraTokens.space12),
                    AleraTextField(
                      controller: draft.identityFile,
                      labelText: 'Identity File',
                      hintText: '~/.ssh/id_ed25519',
                      prefixIcon: AleraIcons.secure,
                      enabled: enabled,
                    ),
                  ],
                  const SizedBox(height: AleraTokens.space16),
                  Row(
                    mainAxisAlignment: .end,
                    children: <Widget>[
                      TextButton(
                        onPressed: dirty && enabled ? draft.revert : null,
                        child: const Text('Revert'),
                      ),
                      const SizedBox(width: AleraTokens.space8),
                      FilledButton(
                        onPressed: dirty && enabled ? onSave : null,
                        child: Text(saving ? 'Saving…' : 'Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

const List<AleraDropdownFieldEntry<String>> _platformEntries =
    <AleraDropdownFieldEntry<String>>[
      AleraDropdownFieldEntry<String>(value: '', label: 'Auto'),
      AleraDropdownFieldEntry<String>(value: 'macos', label: 'macOS'),
      AleraDropdownFieldEntry<String>(value: 'linux', label: 'Linux'),
      AleraDropdownFieldEntry<String>(value: 'windows', label: 'Windows'),
    ];

const List<AleraDropdownFieldEntry<String>> _archEntries =
    <AleraDropdownFieldEntry<String>>[
      AleraDropdownFieldEntry<String>(value: '', label: 'Auto'),
      AleraDropdownFieldEntry<String>(value: 'x64', label: 'x64'),
      AleraDropdownFieldEntry<String>(value: 'arm64', label: 'arm64'),
    ];
