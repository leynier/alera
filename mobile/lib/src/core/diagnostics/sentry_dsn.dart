/// Sentry project DSN for the mobile companion.
///
/// A DSN is not a secret: it is designed to travel inside the client and ends
/// up in the shipped APK either way, so keeping it in the repo avoids threading
/// build secrets through the release workflow for no gain.
///
/// Separate from the desktop project because the two version independently
/// (mobile `0.9.0`, desktop `0.34.0`) and a shared project would make release
/// tracking and issue grouping meaningless.
library;

const String kAleraMobileSentryDsn =
    'https://3b38d7020608969d0672709f47731dbf@o4511816353644544.ingest.us.sentry.io/4511816385626112';
