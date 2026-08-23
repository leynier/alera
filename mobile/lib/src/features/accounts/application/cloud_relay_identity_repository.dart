abstract interface class CloudRelayIdentityRepository {
  Future<String> getOrCreatePrivateKey(String accountId);
}
