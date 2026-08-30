abstract interface class CloudRelayIdentityRepository {
  Future<String> getOrCreatePrivateKey(String accountId);
}

class CloudRelayIdentity {
  const CloudRelayIdentity(this.privateKey, this.keyVersion);
  final String privateKey;
  final int keyVersion;
}

abstract interface class VersionedCloudRelayIdentityRepository
    implements CloudRelayIdentityRepository {
  Future<CloudRelayIdentity> getOrCreateIdentity(String accountId);
  Future<CloudRelayIdentity> rotateIdentity(
    String accountId,
    CloudRelayIdentity previous,
  );
}
