import 'dart:async';
import 'dart:convert';

import 'package:alera_mobile/src/features/accounts/application/cloud_account_providers.dart';
import 'package:alera_mobile/src/features/accounts/application/cloud_accounts_controller.dart';
import 'package:alera_mobile/src/features/hosts/application/host_providers.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/host_reachability.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/runtime/infra/relay_crypto.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'remote_runtime_connection_controller.g.dart';

bool isRelayFallbackTransportFailure(Object error) {
  if (error is HostUnreachableException && error.cause != null) {
    return isHostReachabilityFailure(
      normalizeHostConnectionError(error.cause!),
    );
  }
  return isHostReachabilityFailure(normalizeHostConnectionError(error));
}

Future<MobileRuntimeClient> connectRuntimeThroughRelay(
  Ref ref,
  String accountId,
  String runtimeId,
) async {
  final session = await ref
      .read(cloudAccountsControllerProvider.notifier)
      .sessionForRequest(accountId);
  if (session == null) throw StateError('Cloud account session is missing.');
  final privateKey = await ref
      .read(cloudRelayIdentityRepositoryProvider)
      .getOrCreatePrivateKey(accountId);
  final identity = await RelayIdentityKeyPair.fromPrivate(
    base64Url.decode(base64Url.normalize(privateKey)),
  );
  final installationId = await ref
      .read(cloudAccountRepositoryProvider)
      .getOrCreateInstallationId();
  final api = ref.read(aleraRelayCloudApiProvider);
  final registration = await api.registerRelayIdentity(
    session: session,
    publicKey: base64UrlNoPadding(identity.publicBytes),
    keyVersion: 1,
  );
  if (registration.clientId != installationId ||
      registration.clientKind != 'mobile' ||
      registration.publicKey != base64UrlNoPadding(identity.publicBytes) ||
      registration.keyVersion != 1) {
    throw const FormatException('Cloud returned an invalid mobile identity');
  }
  final grant = await api.requestRelayGrant(
    session: session,
    runtimeId: runtimeId,
  );
  final client = await MobileRuntimeClient.connectRelay(
    grant: grant,
    identity: identity,
  );
  try {
    await client.authenticateRelay(cloudDeviceId: grant.clientId);
    return client;
  } on Object {
    await client.dispose();
    rethrow;
  }
}

@riverpod
class RemoteRuntimeConnectionController
    extends _$RemoteRuntimeConnectionController {
  MobileRuntimeClient? _client;

  @override
  Future<MobileRuntimeClient> build(String accountId, String runtimeId) async {
    ref.onDispose(() {
      unawaited(_client?.dispose());
    });
    final client = await _connectDirectFirst(accountId, runtimeId);
    if (!ref.mounted) {
      await client.dispose();
      throw const RuntimeConnectionLost();
    }
    _client = client;
    return client;
  }

  Future<MobileRuntimeClient> _connectDirectFirst(
    String accountId,
    String runtimeId,
  ) async {
    final hosts = await ref.read(pairedHostsControllerProvider.future);
    final paired = hosts
        .where((host) => host.runtimeId == runtimeId)
        .firstOrNull;
    if (paired != null) {
      try {
        return await _connectDirect(paired.id);
      } on Object catch (error) {
        if (!isRelayFallbackTransportFailure(error)) {
          rethrow;
        }
      }
    }
    return connectRuntimeThroughRelay(ref, accountId, runtimeId);
  }

  Future<MobileRuntimeClient> _connectDirect(String hostId) async {
    final hosts = await ref.read(pairedHostsControllerProvider.future);
    final host = hosts.where((item) => item.id == hostId).firstOrNull;
    if (host == null) throw StateError('Host is not paired.');
    final token = await ref
        .read(hostRepositoryProvider)
        .readDeviceToken(hostId);
    if (token == null || token.trim().isEmpty) {
      throw StateError('Device token is missing.');
    }
    final installationId = await ref
        .read(cloudAccountRepositoryProvider)
        .getOrCreateInstallationId();
    final client = await MobileRuntimeClient.connect(host.endpoint);
    try {
      await client.authenticate(
        deviceId: host.deviceId,
        deviceToken: token,
        cloudDeviceId: installationId,
      );
      return client;
    } on Object {
      await client.dispose();
      rethrow;
    }
  }
}
