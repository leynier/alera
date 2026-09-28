export type InstallPlatform = 'macos' | 'windows' | 'linux' | 'android' | 'ios';

export interface PlatformHints {
  /** `navigator.userAgentData.platform`, where the browser offers it. */
  userAgentDataPlatform?: string;
  userAgent: string;
  maxTouchPoints: number;
}

/**
 * Best guess at the visitor's platform, used only to preselect an install
 * option; every option stays one click away when the guess is wrong.
 */
export function detectInstallPlatform(hints: PlatformHints): InstallPlatform | null {
  const hint = `${hints.userAgentDataPlatform ?? ''} ${hints.userAgent}`.toLowerCase();
  // iPadOS reports a desktop Mac user agent; touch support gives it away.
  const touchMac = hint.includes('mac') && hints.maxTouchPoints > 1;
  if (hint.includes('android')) return 'android';
  if (hint.includes('iphone') || hint.includes('ipad') || touchMac) return 'ios';
  if (hint.includes('win')) return 'windows';
  if (hint.includes('mac')) return 'macos';
  if (hint.includes('linux') || hint.includes('x11') || hint.includes('cros')) return 'linux';
  return null;
}

export function browserPlatformHints(): PlatformHints {
  const client = navigator as Navigator & { userAgentData?: { platform?: string } };
  return {
    userAgentDataPlatform: client.userAgentData?.platform,
    userAgent: navigator.userAgent,
    maxTouchPoints: navigator.maxTouchPoints,
  };
}
