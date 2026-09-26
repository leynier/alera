part of 'mobile_runtime_client.dart';

/// Account enrollment and push-subscription refresh on the paired runtime.
mixin MobileRuntimeCloudRequests {
  Set<String> get runtimeCapabilities;

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  bool get supportsCloudEnrollment =>
      runtimeCapabilities.contains(mobileCloudEnrollmentCapability);

  Future<String> createCloudEnrollment() async {
    if (!supportsCloudEnrollment) {
      throw StateError('This host does not support account enrollment');
    }
    final payload = await requestMap('mobile.cloudEnrollment.create');
    return payload.requiredString('code');
  }

  Future<int> refreshCloudSubscriptions() async {
    if (!supportsCloudEnrollment) {
      throw StateError('This host does not support cloud subscriptions');
    }
    final payload = await requestMap('mobile.cloudSubscriptions.refresh');
    return payload.requiredInt('activeSubscriptions');
  }
}
