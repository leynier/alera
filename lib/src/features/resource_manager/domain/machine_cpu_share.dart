/// Conversion between the sampler's CPU unit and the panel's.
///
/// The host reports what `sysinfo` measures: percent of a single core, so a
/// process spread over four busy cores reads 400%. The panel reports a share of
/// the whole machine, the same framing as the memory column's "% of RAM" and the
/// same number the operating system's own monitor shows, because a reading that
/// cannot be compared against the rest of the machine is not a reading a user
/// can act on.
library;

/// `perCorePercent` expressed against the machine's total CPU capacity.
///
/// Null when the core count is unknown, which is what an unavailable snapshot
/// carries: the panel renders a dash there rather than a fabricated share.
double? machineCpuShare(double? perCorePercent, int coreCount) {
  if (perCorePercent == null || coreCount <= 0) {
    return null;
  }
  return perCorePercent / coreCount;
}
