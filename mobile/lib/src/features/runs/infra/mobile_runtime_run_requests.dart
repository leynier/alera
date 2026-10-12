import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

/// Run support of the paired runtime client; the requests themselves go
/// through the client's generic `requestMap`.
mixin MobileRuntimeRunRequests implements MobileRunsClient {
  Set<String> get runtimeCapabilities;

  @override
  bool get supportsRuns => runtimeCapabilities.contains(mobileRunsCapability);

  @override
  bool get supportsRecipes =>
      runtimeCapabilities.contains(mobileRecipesCapability);
}
