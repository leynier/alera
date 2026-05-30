const String kAleraReleaseFlavor = 'release';
const String kAleraDevFlavor = 'dev';

const String kAleraFlavor = String.fromEnvironment(
  'ALERA_FLAVOR',
  defaultValue: kAleraDevFlavor,
);

const bool kIsAleraReleaseFlavor = kAleraFlavor == kAleraReleaseFlavor;
const bool kIsAleraDevFlavor = !kIsAleraReleaseFlavor;

const String kAleraReleaseAppName = 'Alera';
const String kAleraDevAppName = 'Alera Dev';
const String kAleraReleaseBundleId = 'dev.leynier.alera';
const String kAleraDevBundleId = 'dev.leynier.alera.dev';

const String kAleraAppName = kIsAleraReleaseFlavor
    ? kAleraReleaseAppName
    : kAleraDevAppName;
const String kAleraBundleId = kIsAleraReleaseFlavor
    ? kAleraReleaseBundleId
    : kAleraDevBundleId;

/// Returns the effective value of `autoInstallEnabled` after applying the
/// dev-flavor guard. A dev build can never auto-install, regardless of what
/// the environment says, so this collapses the requested flag to `false` when
/// `isDevBuild` is `true`.
bool effectiveAutoInstallEnabled(bool requested, {bool? isDevBuild}) {
  if (isDevBuild ?? kIsAleraDevFlavor) {
    return false;
  }
  return requested;
}
