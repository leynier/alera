import 'dart:convert';

import 'package:alera_mobile/src/features/hosts/application/host_repository.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalHostRepository implements HostRepository {
  LocalHostRepository({
    FlutterSecureStorage? secureStorage,
    SharedPreferencesAsync? preferences,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _preferences = preferences ?? SharedPreferencesAsync();

  static const String _hostsKey = 'alera.mobile.hosts';
  static const String _deviceTokenPrefix = 'alera.mobile.deviceToken.';

  final FlutterSecureStorage _secureStorage;
  final SharedPreferencesAsync _preferences;

  @override
  Future<List<PairedHostProfile>> loadHosts() async {
    final encoded = await _preferences.getString(_hostsKey);
    if (encoded == null || encoded.trim().isEmpty) {
      return const <PairedHostProfile>[];
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! List<Object?>) {
      return const <PairedHostProfile>[];
    }
    return <PairedHostProfile>[
      for (final item in decoded)
        if (item is Map<String, Object?>) PairedHostProfile.fromJson(item),
    ];
  }

  @override
  Future<void> savePairedHost(
    PairedHostProfile host,
    String deviceToken,
  ) async {
    final hosts = await loadHosts();
    final next = <PairedHostProfile>[
      host,
      for (final existing in hosts)
        if (existing.id != host.id) existing,
    ];
    final tokenKey = '$_deviceTokenPrefix${host.id}';
    final previousToken = await _secureStorage.read(key: tokenKey);
    await _secureStorage.write(key: tokenKey, value: deviceToken);
    try {
      await _writeHosts(next);
    } on Object {
      if (previousToken == null) {
        await _secureStorage.delete(key: tokenKey);
      } else {
        await _secureStorage.write(key: tokenKey, value: previousToken);
      }
      rethrow;
    }
  }

  @override
  Future<void> removeHost(String hostId) async {
    final hosts = await loadHosts();
    await _writeHosts(<PairedHostProfile>[
      for (final host in hosts)
        if (host.id != hostId) host,
    ]);
    await _secureStorage.delete(key: '$_deviceTokenPrefix$hostId');
  }

  @override
  Future<String?> readDeviceToken(String hostId) {
    return _secureStorage.read(key: '$_deviceTokenPrefix$hostId');
  }

  @override
  Future<void> updateHostAlias(String hostId, String? alias) async {
    final hosts = await loadHosts();
    await _writeHosts(<PairedHostProfile>[
      for (final host in hosts)
        if (host.id == hostId) host.withAlias(alias) else host,
    ]);
  }

  Future<void> _writeHosts(List<PairedHostProfile> hosts) {
    return _preferences.setString(
      _hostsKey,
      jsonEncode(hosts.map((host) => host.toJson()).toList(growable: false)),
    );
  }
}
