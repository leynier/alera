import 'package:alera/src/features/account/domain/alera_account_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_change_coalescer.dart';
import 'package:alera/src/shared/infra/runtime/runtime_snapshot_stream.dart';

const Set<String> _accountChangeEvents = <String>{
  'aleraAccountChanged',
  'runtimeSettingsChanged',
};

final class RuntimeAleraAccountRepository(
  final RuntimeHostClient _client, {
  RuntimeChangeCoalescer? coalescer,
}) {
  this : _coalescer = coalescer ?? RuntimeChangeCoalescer();

  final RuntimeChangeCoalescer _coalescer;

  Future<AleraAccountStatus> status() async {
    final account = _map(
      await _client.runtimeRequest('account.status'),
      'account status',
    );
    final settings = _map(
      await _client.runtimeRequest('runtimeSettings.get'),
      'runtime settings',
    );
    return AleraAccountStatus.fromRuntime(
      accountStatus: account,
      runtimeSettings: settings,
    );
  }

  Stream<AleraAccountStatus> watchStatus() {
    return runtimeSnapshotStream(
      client: _client,
      eventNames: _accountChangeEvents,
      readSnapshot: status,
      coalesceKey: 'aleraAccountStatus',
      coalescer: _coalescer,
    );
  }

  Stream<String> watchSignInFailures() {
    return _client.runtimeEvents
        .where((event) => event.name == 'aleraAccountSignInFailed')
        .map(
          (event) => event.payload['message'] as String? ?? 'Sign in failed',
        );
  }

  Future<Uri> startSignIn(AleraIdentityProvider provider) async {
    return _startBrowserFlow('account.signIn.start', provider);
  }

  Future<Uri> startLink(AleraIdentityProvider provider) async {
    return _startBrowserFlow('account.link.start', provider);
  }

  Future<void> cancelSignIn() async {
    await _client.runtimeRequest('account.signIn.cancel');
  }

  Future<void> signOut() async {
    await _client.runtimeRequest('account.signOut');
  }

  Future<void> deleteAccount() async {
    await _client.runtimeRequest('account.delete');
  }

  Future<void> transferRuntime(String targetAccountId) async {
    await _client.runtimeRequest('account.transfer.confirm', <String, Object?>{
      'targetAccountId': targetAccountId,
    });
  }

  Future<void> updatePush(MobilePushPreferences preferences) async {
    await _client.runtimeRequest('runtimeSettings.update', <String, Object?>{
      'mobilePushNotifications': preferences.toJson(),
    });
  }

  Future<Uri> _startBrowserFlow(
    String request,
    AleraIdentityProvider provider,
  ) async {
    final value = _map(
      await _client.runtimeRequest(request, <String, Object?>{
        'provider': provider.wireName,
      }),
      'account authorization',
    );
    final rawUrl = value['authorizationUrl'];
    if (rawUrl is! String) {
      throw const FormatException('Account authorization URL is missing.');
    }
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('Account authorization URL is invalid.');
    }
    return uri;
  }
}

Map<String, Object?> _map(Object? value, String label) {
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  throw FormatException('Runtime $label must be a JSON object.');
}
