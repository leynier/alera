import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';

/// Inbox support of the paired runtime client; the requests themselves go
/// through the client's generic `requestMap`.
mixin MobileRuntimeInboxRequests implements MobileInboxClient {
  Set<String> get runtimeCapabilities;

  @override
  bool get supportsInbox => runtimeCapabilities.contains(mobileInboxCapability);
}
