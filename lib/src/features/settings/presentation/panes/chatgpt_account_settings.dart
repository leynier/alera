import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_setting_row.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/settings/presentation/panes/chatgpt_account_rows.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/logging/log_redaction.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:alera/src/shared/infra/uri/uri_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _Availability { loading, unsupported, failed, ready }

/// ChatGPT account registrations on this runtime: connect, switch, reconnect
/// and sign out. Credentials stay in the runtime; this widget only sees
/// labels and connection state.
class const ChatGptAccountSettings({
  super.key,
  required final VoidCallback onAccountChanged,
  final VoidCallback? onAccountReady,
  final RuntimeHostClient? client,
  final ExternalUriLauncher? launcher,
  final Duration pollInterval = const Duration(seconds: 1),
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ChatGptAccountSettings> createState() =>
      _ChatGptAccountSettingsState();
}

class _ChatGptAccountSettingsState
    extends ConsumerState<ChatGptAccountSettings> {
  _Availability _availability = .loading;
  List<ChatGptAccount> _accounts = const <ChatGptAccount>[];
  String? _activeClientId;
  bool _pending = false;
  String? _runtimeError;
  String? _actionError;
  String? _busyKey;
  bool _noticeShown = false;
  int _generation = 0;
  Timer? _poll;

  RuntimeHostClient get _client =>
      widget.client ?? ref.read(runtimeHostClientProvider);
  ExternalUriLauncher get _launcher =>
      widget.launcher ?? ref.read(externalUriLauncherProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  @override
  void dispose() {
    // A pending sign-in keeps running in the runtime, so finishing it in the
    // browser after leaving Settings still connects the account.
    _poll?.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(
    String action, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    final value = await _client.runtimeRequest(
      'aiAssist.chatgpt.$action',
      payload,
      const Duration(seconds: 70),
    );
    if (value is! Map) {
      throw StateError('ChatGPT returned an invalid response.');
    }
    return Map<String, dynamic>.from(value);
  }

  Future<bool> _supported() async {
    if (_availability == .ready) return true;
    final client = _client;
    return client is RuntimeHostCapabilityClient &&
        await (client as RuntimeHostCapabilityClient).supportsRuntimeCapability(
          aleraRuntimeHostAiAssistChatGptCapability,
        );
  }

  Future<void> _refresh() async {
    final generation = ++_generation;
    _poll?.cancel();
    try {
      if (!await _supported()) {
        if (mounted && generation == _generation) {
          setState(() => _availability = .unsupported);
        }
        return;
      }
      final status = await _request('status');
      if (!mounted || generation != _generation) return;
      _apply(status);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (_availability != .ready) _availability = .failed;
        _runtimeError = 'ChatGPT account status couldn’t be loaded.';
      });
    }
  }

  void _apply(Map<String, dynamic> status) {
    final wasReady = _availability == .ready;
    final wasPending = _pending;
    final previousActive = _activeClientId;
    final pending = status['pending'] == true;
    final activeClientId = status['activeClientId'] as String?;
    setState(() {
      _availability = .ready;
      _accounts = <ChatGptAccount>[
        for (final value in status['accounts'] as List? ?? const <Object?>[])
          ?ChatGptAccount.fromJson(value),
      ];
      _activeClientId = activeClientId;
      _pending = pending;
      _runtimeError = status['error'] as String?;
    });
    if (wasReady && previousActive != _activeClientId) {
      widget.onAccountChanged();
    }
    final accountBecameReady =
        activeClientId != null &&
        !pending &&
        ((!wasReady && !wasPending) ||
            wasPending && previousActive == activeClientId);
    if (accountBecameReady) {
      widget.onAccountReady?.call();
    }
    if (pending) {
      _poll = Timer(widget.pollInterval, () => unawaited(_refresh()));
    }
    if (status['showPlanNotice'] == true && !_noticeShown) {
      _noticeShown = true;
      unawaited(_showPlanNotice());
    }
  }

  Future<void> _showPlanNotice() async {
    await showChatGptPlanNotice(context);
    try {
      await _request('acknowledgePlan');
    } catch (_) {
      // The runtime shows the notice again next time; nothing to recover here.
    }
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    if (_busyKey != null) return;
    setState(() {
      _busyKey = key;
      _actionError = null;
    });
    try {
      await action();
    } on StateError catch (error) {
      if (mounted) setState(() => _actionError = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _actionError = 'ChatGPT didn’t respond. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
    if (mounted) await _refresh();
  }

  Future<void> _signIn(String? clientId) =>
      _run('signIn:${clientId ?? ''}', () async {
        final result = await _request('signIn', <String, Object?>{
          'clientId': ?clientId,
        });
        final uri = Uri.tryParse(result['authorizationUrl']?.toString() ?? '');
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host != 'auth.openai.com' ||
            uri.path != '/api/accounts/authorize') {
          await _request('cancel');
          throw StateError('ChatGPT returned an invalid sign-in link.');
        }
        registerLogSecret(uri.toString());
        try {
          await _launcher.open(uri);
        } catch (_) {
          await _request('cancel');
          throw StateError('Your browser couldn’t be opened. Try again.');
        }
      });

  Future<void> _select(String clientId) => _run(
    'select:$clientId',
    () => _request('select', <String, Object?>{'clientId': clientId}),
  );

  Future<void> _signOut(String clientId) => _run(
    'signOut:$clientId',
    () => _request('signOut', <String, Object?>{'clientId': clientId}),
  );

  Future<void> _cancel() => _run('cancel', () => _request('cancel'));

  Future<void> _openUsage() async {
    setState(() => _actionError = null);
    try {
      await _launcher.open(chatGptUsageUri);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _actionError = 'ChatGPT settings couldn’t be opened. Try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraSettingsGroup(
      title: 'ChatGPT Account',
      description: 'Use your ChatGPT plan for AI Assist text. Eligible requests use your plan or credits balance.',
      children: switch (_availability) {
        .loading => <Widget>[
          const AleraSettingRow(
            title: 'Account',
            description: 'Checking for ChatGPT accounts on this computer.',
            // Static placeholder: the status call may never answer offline.
            child: Align(
              alignment: .centerRight,
              child: ChatGptSignInButton(onPressed: null),
            ),
          ),
        ],
        .unsupported => <Widget>[
          _notice(
            'This runtime can’t connect ChatGPT. Update Alera, then check again.',
            tone: .warning,
            action: _noticeAction('Check Again', _refresh),
          ),
        ],
        .failed => <Widget>[
          _notice(
            _runtimeError ?? 'ChatGPT account status couldn’t be loaded.',
            tone: .error,
            action: _noticeAction('Try Again', _refresh),
          ),
        ],
        .ready => _readyRows(),
      },
    );
  }

  List<Widget> _readyRows() {
    final locked = _busyKey != null || _pending;
    final error = _actionError ?? _runtimeError;
    return <Widget>[
      if (_pending)
        AleraSettingRow(
          title: 'Signing In',
          description: 'Finish signing in to ChatGPT in your browser.',
          child: Align(
            alignment: .centerRight,
            child: OutlinedButton(
              onPressed: _busyKey == null ? () => unawaited(_cancel()) : null,
              child: _BusyText('Cancel Sign-In', busy: _busyKey == 'cancel'),
            ),
          ),
        ),
      if (error != null) _notice(error, tone: .error),
      for (final account in _accounts)
        ChatGptAccountRow(
          key: ValueKey<String>('chatgpt-account-${account.clientId}'),
          account: account,
          active: account.clientId == _activeClientId,
          actions: _accountActions(account, locked: locked),
        ),
      AleraSettingRow(
        title: _accounts.isEmpty ? 'Connect Account' : 'Add Account',
        description: _accounts.isEmpty
            ? 'Sign in to use your ChatGPT plan on this computer.'
            : 'Sign in with a different ChatGPT account.',
        child: Align(
          alignment: .centerRight,
          child: ChatGptSignInButton(
            busy: _busyKey == 'signIn:',
            onPressed: locked ? null : () => unawaited(_signIn(null)),
            semanticsLabel: _accounts.isEmpty
                ? null
                : '$chatGptSignInLabel with another account',
          ),
        ),
      ),
      if (_accounts.any((account) => account.connected))
        AleraSettingRow(
          title: 'Plan Usage',
          description: 'Review limits and credits for Alera in ChatGPT.',
          child: Align(
            alignment: .centerRight,
            child: OutlinedButton.icon(
              icon: const Icon(AleraIcons.external, size: AleraTokens.iconMd),
              label: const Text(chatGptManageUsageLabel),
              onPressed: () => unawaited(_openUsage()),
            ),
          ),
        ),
    ];
  }

  List<Widget> _accountActions(ChatGptAccount account, {required bool locked}) {
    final id = account.clientId;
    final active = id == _activeClientId;
    return <Widget>[
      if (!account.ready)
        ChatGptSignInButton(
          busy: _busyKey == 'signIn:$id',
          onPressed: locked ? null : () => unawaited(_signIn(id)),
          semanticsLabel: '$chatGptSignInLabel as ${account.label}',
        )
      else if (!active)
        OutlinedButton(
          onPressed: locked ? null : () => unawaited(_select(id)),
          child: _BusyText(
            'Use Account',
            semanticsLabel: 'Use ${account.label} for AI Assist',
            busy: _busyKey == 'select:$id',
          ),
        ),
      if (account.connected)
        TextButton(
          // The app theme pins TextButton foreground for every state.
          style: TextButton.styleFrom(
            foregroundColor: AleraTokens.foreground,
            disabledForegroundColor: AleraTokens.foregroundFaint,
          ),
          onPressed: locked ? null : () => unawaited(_signOut(id)),
          child: _BusyText(
            'Sign Out',
            semanticsLabel: 'Sign out of ${account.label}',
            busy: _busyKey == 'signOut:$id',
          ),
        ),
    ];
  }

  Widget _noticeAction(String label, Future<void> Function() onPressed) =>
      Align(
        alignment: .centerLeft,
        child: OutlinedButton(
          onPressed: () => unawaited(onPressed()),
          child: Text(label),
        ),
      );

  Widget _notice(
    String message, {
    AleraInlineNoticeTone tone = .info,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.all(AleraTokens.space12),
    child: Semantics(
      liveRegion: true,
      child: AleraInlineNotice(message: message, tone: tone, child: action),
    ),
  );
}

/// Button text that swaps to a spinner without changing the button's width.
class const _BusyText(
  final String label, {
  required final bool busy,
  final String? semanticsLabel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: .center,
      children: <Widget>[
        Opacity(
          opacity: busy ? 0 : 1,
          child: Text(label, semanticsLabel: semanticsLabel),
        ),
        if (busy) const ChatGptButtonSpinner(),
      ],
    );
  }
}
