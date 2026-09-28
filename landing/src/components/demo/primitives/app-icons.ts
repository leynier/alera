import Activity from '@lucide/astro/icons/activity';
import ArrowLeft from '@lucide/astro/icons/arrow-left';
import BellRing from '@lucide/astro/icons/bell-ring';
import Bot from '@lucide/astro/icons/bot';
import Check from '@lucide/astro/icons/check';
import ChevronDown from '@lucide/astro/icons/chevron-down';
import ChevronRight from '@lucide/astro/icons/chevron-right';
import ChevronUp from '@lucide/astro/icons/chevron-up';
import ChevronsDownUp from '@lucide/astro/icons/chevrons-down-up';
import ChevronsLeft from '@lucide/astro/icons/chevrons-left';
import ChevronsRight from '@lucide/astro/icons/chevrons-right';
import Circle from '@lucide/astro/icons/circle';
import CircleAlert from '@lucide/astro/icons/circle-alert';
import CircleCheck from '@lucide/astro/icons/circle-check';
import CircleX from '@lucide/astro/icons/circle-x';
import Coffee from '@lucide/astro/icons/coffee';
import Copy from '@lucide/astro/icons/copy';
import Ellipsis from '@lucide/astro/icons/ellipsis';
import Eye from '@lucide/astro/icons/eye';
import File from '@lucide/astro/icons/file';
import FileText from '@lucide/astro/icons/file-text';
import Folder from '@lucide/astro/icons/folder';
import FolderGit2 from '@lucide/astro/icons/folder-git-2';
import FolderPlus from '@lucide/astro/icons/folder-plus';
import Gauge from '@lucide/astro/icons/gauge';
import GitBranch from '@lucide/astro/icons/git-branch';
import GitCompare from '@lucide/astro/icons/git-compare';
import GitFork from '@lucide/astro/icons/git-fork';
import GitMerge from '@lucide/astro/icons/git-merge';
import GitPullRequest from '@lucide/astro/icons/git-pull-request';
import House from '@lucide/astro/icons/house';
import Keyboard from '@lucide/astro/icons/keyboard';
import ListChecks from '@lucide/astro/icons/list-checks';
import LoaderCircle from '@lucide/astro/icons/loader-circle';
import MessageSquare from '@lucide/astro/icons/message-square';
import MessageSquarePlus from '@lucide/astro/icons/message-square-plus';
import Mic from '@lucide/astro/icons/mic';
import PanelLeft from '@lucide/astro/icons/panel-left';
import Pin from '@lucide/astro/icons/pin';
import Plus from '@lucide/astro/icons/plus';
import RefreshCw from '@lucide/astro/icons/refresh-cw';
import Search from '@lucide/astro/icons/search';
import Send from '@lucide/astro/icons/send';
import Server from '@lucide/astro/icons/server';
import Settings from '@lucide/astro/icons/settings';
import SlidersHorizontal from '@lucide/astro/icons/sliders-horizontal';
import Smartphone from '@lucide/astro/icons/smartphone';
import Sparkles from '@lucide/astro/icons/sparkles';
import Split from '@lucide/astro/icons/split';
import Terminal from '@lucide/astro/icons/terminal';
import TriangleAlert from '@lucide/astro/icons/triangle-alert';
import UserRound from '@lucide/astro/icons/user-round';
import X from '@lucide/astro/icons/x';

/**
 * The demo names icons by their `AleraIcons` role, never by glyph, and each
 * role resolves to the Lucide icon `lib/src/design_system/icons/alera_icons.dart`
 * assigns it. The fidelity tests read this file and fail when a role here
 * disagrees with the app. Lucide renamed `home` to `house`; the app's
 * `LucideIcons.home` is the same glyph.
 */
export const APP_ICONS = {
  add: Plus,
  close: X,
  copy: Copy,
  refresh: RefreshCw,
  cancel: CircleX,
  check: Check,
  send: Send,
  mic: Mic,
  pin: Pin,
  search: Search,
  chevronUp: ChevronUp,
  chevronDown: ChevronDown,
  chevronRight: ChevronRight,
  chevronsLeft: ChevronsLeft,
  chevronsRight: ChevronsRight,
  collapseAll: ChevronsDownUp,
  back: ArrowLeft,
  more: Ellipsis,
  folder: Folder,
  newFolder: FolderPlus,
  folderSpecial: FolderGit2,
  file: FileText,
  fileGeneric: File,
  host: Server,
  mobileDevice: Smartphone,
  account: UserRound,
  workspaceMain: House,
  split: Split,
  gitBranch: GitBranch,
  gitFork: GitFork,
  gitMerge: GitMerge,
  gitPullRequest: GitPullRequest,
  checks: ListChecks,
  diff: GitCompare,
  success: CircleCheck,
  error: CircleAlert,
  loading: LoaderCircle,
  circle: Circle,
  notifications: BellRing,
  visible: Eye,
  sidebarToggle: PanelLeft,
  settings: Settings,
  tune: SlidersHorizontal,
  agent: Bot,
  quota: Gauge,
  resources: Activity,
  keepAlive: Coffee,
  warning: TriangleAlert,
  terminal: Terminal,
  keyboard: Keyboard,
  composer: MessageSquarePlus,
  comment: MessageSquare,
  ai: Sparkles,
} as const;

export type AppIconRole = keyof typeof APP_ICONS;
