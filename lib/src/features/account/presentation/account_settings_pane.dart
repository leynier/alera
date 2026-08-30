import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/account/application/alera_account_providers.dart';
import 'package:alera/src/features/account/domain/alera_account_status.dart';
import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const AccountSettingsPane({
  super.key,
  final Map<String, GlobalKey> groupKeys = const <String, GlobalKey>{},
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AccountSettingsPane> createState() =>
      _AccountSettingsPaneState();
}

class _AccountSettingsPaneState extends ConsumerState<AccountSettingsPane> {
  final TextEditingController _transferTargetController =
      TextEditingController();

  @override
  void dispose() {
    _transferTargetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(aleraAccountSignInFailureProvider, (_, next) {
      next.whenData((message) => _showError('Sign in failed: $message'));
    });
    ref.listen(aleraAccountActionsProvider, (_, next) {
      if (next case AsyncError(:final error)) {
        _showError(_cleanError(error));
      }
    });

    final status = ref.watch(aleraAccountStatusProvider);
    final busy = ref.watch(aleraAccountActionsProvider).isLoading;
    return status.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => AleraEmptyState(
        icon: AleraIcons.account,
        title: 'Account unavailable',
        message: _cleanError(error),
      ),
      data: (value) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: .stretch,
          children: <Widget>[
            KeyedSubtree(
              key: widget.groupKeys['identity'],
              child: _identityGroup(value, busy),
            ),
            const SizedBox(height: AleraTokens.space16),
            KeyedSubtree(
              key: widget.groupKeys['push'],
              child: _pushGroup(value, busy),
            ),
            const SizedBox(height: AleraTokens.space16),
            KeyedSubtree(
              key: widget.groupKeys['ownership'],
              child: _ownershipGroup(value, busy),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identityGroup(AleraAccountStatus status, bool busy) {
    final account = status.account;
    return AleraSettingsGroup(
      title: 'Identity',
      description: 'Your Alera identity protects cloud delivery and stays optional for local features.',
      children: <Widget>[
        if (account == null) ...<Widget>[
          SettingsButtonRow(
            title: 'Continue With Google',
            description: 'Sign in through your default browser.',
            buttonLabel: 'Google',
            onPressed: busy ? null : () => _actions.signIn(.google),
          ),
          SettingsButtonRow(
            title: 'Continue With GitHub',
            description: 'Uses profile and verified email access only. Repository access is never requested.',
            buttonLabel: 'GitHub',
            onPressed: busy ? null : () => _actions.signIn(.github),
          ),
        ] else ...<Widget>[
          AleraSettingRow(
            title: 'Alera Account',
            description: 'Runtime ${account.runtimeId}',
            controlWidth: 280,
            child: Column(
              crossAxisAlignment: .end,
              children: <Widget>[
                Text(
                  account.email,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AleraTokens.space6),
                Wrap(
                  spacing: AleraTokens.space4,
                  runSpacing: AleraTokens.space4,
                  alignment: .end,
                  children: <Widget>[
                    for (final provider in account.providers)
                      AleraChip(label: provider.label),
                  ],
                ),
              ],
            ),
          ),
          for (final provider in AleraIdentityProvider.values)
            if (!account.providers.contains(provider))
              SettingsButtonRow(
                title: 'Link ${provider.label}',
                description:
                    'Add another verified sign-in method to this account.',
                buttonLabel: 'Link',
                onPressed: busy ? null : () => _actions.link(provider),
              ),
          SettingsButtonRow(
            title: 'Sign Out',
            description: 'Stops cloud push delivery from this runtime until you sign in again.',
            buttonLabel: 'Sign Out',
            onPressed: busy ? null : _actions.signOut,
          ),
        ],
        if (status.signInPending)
          SettingsButtonRow(
            title: 'Browser Sign In',
            description: 'A provider authorization is waiting in your browser.',
            buttonLabel: 'Cancel',
            onPressed: busy ? null : _actions.cancelSignIn,
          ),
      ],
    );
  }

  Widget _pushGroup(AleraAccountStatus status, bool busy) {
    final enabled = status.connected && !busy;
    final preferences = status.push;
    final subscriptionCount = status.account?.pushSubscriptionCount ?? 0;
    return AleraSettingsGroup(
      title: 'Mobile Push',
      description: 'Notifications are delivered only to mobile devices enrolled in this account.',
      children: <Widget>[
        _switchRow(
          title: 'Enable Mobile Push',
          description: status.connected
              ? '$subscriptionCount active mobile subscription(s).'
              : 'Sign in before enabling cloud delivery.',
          value: preferences.enabled,
          enabled: enabled,
          onChanged: (value) =>
              _updatePush(preferences.copyWith(enabled: value)),
        ),
        _switchRow(
          title: 'Attention Required',
          description: 'Notify for waiting or blocked agents, decision gates, and escalations.',
          value: preferences.attention,
          enabled: enabled,
          onChanged: (value) =>
              _updatePush(preferences.copyWith(attention: value)),
        ),
        _switchRow(
          title: 'Agent Finished',
          description: 'Notify when an agent finishes a turn.',
          value: preferences.done,
          enabled: enabled,
          onChanged: (value) => _updatePush(preferences.copyWith(done: value)),
        ),
        _switchRow(
          title: 'Terminal Ended',
          description: 'Notify when a terminal session exits or is closed.',
          value: preferences.terminalExit,
          enabled: enabled,
          onChanged: (value) =>
              _updatePush(preferences.copyWith(terminalExit: value)),
        ),
      ],
    );
  }

  Widget _ownershipGroup(AleraAccountStatus status, bool busy) {
    final connected = status.connected;
    return AleraSettingsGroup(
      title: 'Ownership',
      description:
          'Move this runtime to another account or remove your cloud identity.',
      children: <Widget>[
        AleraSettingRow(
          title: 'Target Account ID',
          description: 'Moving a runtime signs this installation out and requires authentication again.',
          child: AleraTextField(
            controller: _transferTargetController,
            hintText: 'Account ID',
            enabled: connected && !busy,
            onChanged: (_) => setState(() {}),
          ),
        ),
        SettingsButtonRow(
          title: 'Move This Runtime',
          description:
              'Transfer runtime ownership and its mobile subscriptions.',
          buttonLabel: 'Move Runtime',
          onPressed:
              connected &&
                  !busy &&
                  _transferTargetController.text.trim().isNotEmpty
              ? _confirmTransfer
              : null,
        ),
        SettingsButtonRow(
          title: 'Delete Alera Account',
          description: 'Permanently removes provider identities, cloud sessions, subscriptions, and quota records.',
          buttonLabel: 'Delete Account',
          onPressed: connected && !busy ? _confirmDelete : null,
        ),
      ],
    );
  }

  AleraSettingRow _switchRow({
    required String title,
    required String description,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return AleraSettingRow(
      title: title,
      description: description,
      child: Align(
        alignment: Alignment.centerRight,
        child: Switch(value: value, onChanged: enabled ? onChanged : null),
      ),
    );
  }

  AleraAccountActions get _actions =>
      ref.read(aleraAccountActionsProvider.notifier);

  Future<void> _updatePush(MobilePushPreferences preferences) {
    return _actions.updatePush(preferences);
  }

  Future<void> _confirmTransfer() async {
    final target = _transferTargetController.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Move This Runtime',
        message:
            'Transfer this runtime and its mobile subscriptions to account $target? This installation will sign out.',
        confirmLabel: 'Move Runtime',
        destructive: true,
      ),
    );
    if (confirmed == true && mounted) {
      await _actions.transferRuntime(target);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const AleraConfirmDialog(
        title: 'Delete Alera Account',
        message: 'This permanently removes your Alera cloud identity, active sessions, mobile subscriptions, and quota records. Recent sign-in may be required.',
        confirmLabel: 'Delete Account',
        destructive: true,
      ),
    );
    if (confirmed == true && mounted) {
      await _actions.deleteAccount();
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

String _cleanError(Object error) {
  return error.toString().replaceFirst(
    RegExp(r'^(StateError|Exception):\s*'),
    '',
  );
}
