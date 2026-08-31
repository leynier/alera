import 'package:alera/src/features/pull_requests/application/forge_provider.dart';
import 'package:alera/src/shared/git_hosting/domain/git_hosting_provider.dart';

/// Looks up the [ForgeProvider] implementation for a resolved provider. Adding
/// a new forge is a matter of registering it here; the rest of the feature is
/// provider-agnostic.
class ForgeProviderRegistry(List<ForgeProvider> providers) {
  this
    : _byId = <GitHostingProvider, ForgeProvider>{
        for (final provider in providers) provider.id: provider,
      };

  final Map<GitHostingProvider, ForgeProvider> _byId;

  /// The provider for [id], or null when unsupported.
  ForgeProvider? forProvider(GitHostingProvider id) => _byId[id];
}
