/// Version of the mobile companion protocol spoken with the Alera runtime
/// gateway. The runtime enforces strict equality during `mobile.hello`, so new
/// capabilities are feature-detected instead of bumping this value.
const int aleraMobileProtocolVersion = 1;

const String mobileCloudEnrollmentCapability = 'mobileCloudEnrollmentV1';
const String mobilePromptImageUploadCapability = 'mobilePromptImageUploadV1';
const String automationsCapability = 'automationsV1';
const String aiDictationCapability = 'aiDictationV1';
const String aiDictationModelsCapability = 'aiDictationModelsV2';
const String aiDictationBackendsCapability = 'aiDictationBackendsV3';
const String remoteAiDictationCapability = 'aiDictationRemoteProvidersV1';
const String mobileExplorerCapability = 'mobileExplorerV1';
const String mobileWorkspaceSearchCapability = 'mobileWorkspaceSearchV1';
const String mobileSourceControlCapability = 'mobileSourceControlV1';
const String mobilePullRequestCapability = 'mobilePullRequestV1';
const String mobilePullRequestActionsCapability = 'mobilePullRequestActionsV1';

/// Linked issues (`linkedIssue.*`, `issue.fetch`, `issueUrl` on
/// `workspace.createManaged`). Additive: never bump the protocol version.
const String linkedIssuesCapability = 'linkedIssuesV1';
