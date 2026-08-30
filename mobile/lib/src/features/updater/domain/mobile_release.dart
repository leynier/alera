/// A published Android build the app can offer to install.
class const MobileRelease({
  required final MobileVersion version,
  required final String tag,
  required final Uri apkUrl,
});

/// The `major.minor.patch` core of a mobile release.
///
/// Mobile ships on its own version sequence with a `-mobile` tag suffix, and
/// release candidates carry a `-rc.N` segment that the app must never offer as
/// an upgrade, so the parser only accepts a stable core.
class const MobileVersion(final int major, final int minor, final int patch)
    implements Comparable<MobileVersion> {
  static final RegExp _core = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');
  static final RegExp _stableTag = RegExp(r'^v(\d+)\.(\d+)\.(\d+)-mobile$');

  /// Parses `1.2.3`, ignoring a `+build` suffix so a pubspec version works.
  static MobileVersion? tryParse(String value) {
    final core = value.trim().split('+').first;
    final match = _core.firstMatch(core);
    if (match == null) {
      return null;
    }
    return MobileVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// Parses `v1.2.3-mobile`. A desktop tag or an rc tag returns null, which is
  /// what keeps both out of the mobile upgrade path.
  static MobileVersion? tryParseTag(String tag) {
    final match = _stableTag.firstMatch(tag.trim());
    if (match == null) {
      return null;
    }
    return MobileVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  bool isNewerThan(MobileVersion other) => compareTo(other) > 0;

  @override
  int compareTo(MobileVersion other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) {
      return majorOrder;
    }
    final minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) {
      return minorOrder;
    }
    return patch.compareTo(other.patch);
  }

  @override
  bool operator ==(Object other) {
    return other is MobileVersion &&
        other.major == major &&
        other.minor == minor &&
        other.patch == patch;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// The universal APK, the only asset the app offers.
///
/// The release also publishes per-ABI APKs, and picking one of those would mean
/// resolving the device's ABI and getting it wrong on a device that reports
/// several. The universal build installs everywhere.
String universalApkAssetName(MobileVersion version) {
  return 'alera-$version-android.apk';
}
