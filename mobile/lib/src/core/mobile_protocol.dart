/// Version of the mobile companion protocol spoken with the Alera runtime
/// gateway. The runtime enforces strict equality during `mobile.hello`, so new
/// capabilities are feature-detected instead of bumping this value.
const int aleraMobileProtocolVersion = 1;

const String mobileCloudEnrollmentCapability = 'mobileCloudEnrollmentV1';
const String mobilePromptImageUploadCapability = 'mobilePromptImageUploadV1';
