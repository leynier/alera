/// Sentry project DSNs.
///
/// A DSN is not a secret: it is designed to travel inside the client and ends
/// up in the distributed binary either way, so keeping it in the repo avoids
/// threading build secrets through every release workflow for no gain.
///
/// One project per surface, because desktop, mobile and the sidecar version
/// independently and a shared project would make release tracking and issue
/// grouping meaningless.
library;

const String kAleraDesktopSentryDsn =
    'https://78d67dfb2e865b558f8ab133546d4ec4@o4511816353644544.ingest.us.sentry.io/4511816381497344';
