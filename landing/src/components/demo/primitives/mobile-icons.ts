import Bell from '@lucide/astro/icons/bell';
import ChevronDown from '@lucide/astro/icons/chevron-down';
import ChevronUp from '@lucide/astro/icons/chevron-up';
import CircleCheck from '@lucide/astro/icons/circle-check';
import CircleX from '@lucide/astro/icons/circle-x';
import Clipboard from '@lucide/astro/icons/clipboard';
import EllipsisVertical from '@lucide/astro/icons/ellipsis-vertical';
import Eye from '@lucide/astro/icons/eye';
import Folder from '@lucide/astro/icons/folder';
import FolderOpen from '@lucide/astro/icons/folder-open';
import GitPullRequest from '@lucide/astro/icons/git-pull-request';
import Plus from '@lucide/astro/icons/plus';
import RefreshCw from '@lucide/astro/icons/refresh-cw';
import Search from '@lucide/astro/icons/search';
import SlidersHorizontal from '@lucide/astro/icons/sliders-horizontal';
import Split from '@lucide/astro/icons/split';

/**
 * The phone app keeps its own icon registry
 * (`mobile/lib/src/design_system/icons/alera_icons.dart`). Most roles match
 * the desktop, a few do not (`more` is the vertical ellipsis, `notifications`
 * is a plain bell), so the phone scene resolves roles through this map, and
 * the fidelity tests check it against that file.
 */
export const MOBILE_ICONS = {
  more: EllipsisVertical,
  chevronUp: ChevronUp,
  chevronDown: ChevronDown,
  split: Split,
  success: CircleCheck,
  notifications: Bell,
  cancel: CircleX,
  search: Search,
  tune: SlidersHorizontal,
  add: Plus,
  paste: Clipboard,
  refresh: RefreshCw,
  gitPullRequest: GitPullRequest,
  visible: Eye,
  folder: Folder,
  folderOpen: FolderOpen,
} as const;

export type MobileIconRole = keyof typeof MOBILE_ICONS;
