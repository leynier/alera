import 'package:alera/src/design_system/icons/alera_codicons.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Semantic icon registry for Alera.
///
/// Icons are referenced by their semantic role (e.g. [delete], [gitBranch]),
/// never by raw glyph, so the whole app stays consistent and the underlying
/// icon set can be swapped from a single place. Most glyphs come from Lucide
/// (`lucide_icons_flutter`), while source-control actions use VS Code Codicons
/// so Git controls follow the conventions developers already know. This class
/// is the only entry point to either icon family.
///
/// File-type icons in the explorer keep using `vscode_material_icon_theme`
/// (the VSCode standard for file trees); see `AleraFileIcon`.
abstract final class AleraIcons {
  const AleraIcons._();

  // Actions
  static const IconData add = LucideIcons.plus;
  static const IconData remove = LucideIcons.minus;
  static const IconData close = LucideIcons.x;
  static const IconData edit = LucideIcons.pencil;
  static const IconData delete = LucideIcons.trash2;
  static const IconData save = LucideIcons.save;
  static const IconData copy = LucideIcons.copy;
  static const IconData duplicate = LucideIcons.copyPlus;
  static const IconData cut = LucideIcons.scissors;
  static const IconData paste = LucideIcons.clipboard;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData sync = LucideIcons.refreshCw;
  static const IconData restart = LucideIcons.rotateCcw;
  static const IconData restore = LucideIcons.history;
  static const IconData cancel = LucideIcons.circleX;
  static const IconData blocked = LucideIcons.ban;
  static const IconData check = LucideIcons.check;
  static const IconData doneAll = LucideIcons.checkCheck;
  static const IconData send = LucideIcons.send;
  static const IconData mic = LucideIcons.mic;
  static const IconData pin = LucideIcons.pin;
  static const IconData pinOff = LucideIcons.pinOff;

  // Search
  static const IconData search = LucideIcons.search;
  static const IconData searchOff = LucideIcons.searchX;
  static const IconData searchManage = LucideIcons.textSearch;
  static const IconData findReplace = LucideIcons.replace;

  // Navigation
  static const IconData chevronUp = LucideIcons.chevronUp;
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData chevronLeft = LucideIcons.chevronLeft;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData chevronsLeft = LucideIcons.chevronsLeft;
  static const IconData chevronsRight = LucideIcons.chevronsRight;
  static const IconData expandAll = LucideIcons.chevronsUpDown;
  static const IconData collapseAll = LucideIcons.chevronsDownUp;
  static const IconData arrowUp = LucideIcons.arrowUp;
  static const IconData arrowDown = LucideIcons.arrowDown;
  static const IconData back = LucideIcons.arrowLeft;
  static const IconData forward = LucideIcons.arrowRight;
  static const IconData more = LucideIcons.ellipsis;
  static const IconData dragHandle = LucideIcons.gripVertical;

  // Files and folders
  static const IconData folder = LucideIcons.folder;
  static const IconData folderOpen = LucideIcons.folderOpen;
  static const IconData newFolder = LucideIcons.folderPlus;
  static const IconData folderOff = LucideIcons.folderX;
  // Project/workspace pickers: a project is a git folder.
  static const IconData folderSpecial = LucideIcons.folderGit2;
  static const IconData file = LucideIcons.fileText;
  static const IconData fileGeneric = LucideIcons.file;
  static const IconData newFile = LucideIcons.filePlus;
  static const IconData copyFiles = LucideIcons.files;
  static const IconData symlink = LucideIcons.link;
  static const IconData link = LucideIcons.link;
  static const IconData unlink = LucideIcons.unlink;
  static const IconData unarchive = LucideIcons.archiveRestore;

  // Workspace graph
  static const IconData host = LucideIcons.server;
  static const IconData tag = LucideIcons.tag;

  // Mobile companion
  static const IconData mobileDevice = LucideIcons.smartphone;
  static const IconData qrCode = LucideIcons.qrCode;
  static const IconData account = LucideIcons.userRound;

  /// Main/default worktree (root of the project workspace graph).
  static const IconData workspaceMain = LucideIcons.home;

  /// Parent/child workspace lineage (matches Orca's workflow glyph).
  static const IconData workspaceChildren = LucideIcons.workflow;

  // Git / version control
  static const IconData gitBranch = LucideIcons.gitBranch;
  static const IconData gitGraph = LucideIcons.gitGraph;
  static const IconData gitFork = LucideIcons.gitFork;
  static const IconData gitMerge = LucideIcons.gitMerge;
  static const IconData gitPullRequest = LucideIcons.gitPullRequest;
  static const IconData gitPullRequestClosed = LucideIcons.gitPullRequestClosed;
  static const IconData checks = LucideIcons.listChecks;
  static const IconData diff = LucideIcons.gitCompare;

  // Source control actions
  static const IconData gitCommit = AleraCodicons.check;
  static const IconData gitAmend = AleraCodicons.check;
  static const IconData gitStage = AleraCodicons.add;
  static const IconData gitUnstage = AleraCodicons.remove;
  static const IconData gitDiscard = AleraCodicons.discard;
  static const IconData gitFetch = AleraCodicons.gitFetch;
  static const IconData gitPull = AleraCodicons.repoPull;
  static const IconData gitPush = AleraCodicons.repoPush;
  static const IconData gitSync = AleraCodicons.sync;
  static const IconData gitPublish = AleraCodicons.cloudUpload;
  static const IconData gitStash = AleraCodicons.gitStash;
  static const IconData gitStashPop = AleraCodicons.gitStashPop;
  static const IconData gitRefresh = AleraCodicons.refresh;

  // Download / upload
  static const IconData download = LucideIcons.download;
  static const IconData downloading = LucideIcons.loaderCircle;
  static const IconData downloadOffline = LucideIcons.cloudDownload;
  // App updater: distinct from a plain file download.
  static const IconData updateAvailable = LucideIcons.hardDriveDownload;
  static const IconData cloudDownload = LucideIcons.cloudDownload;
  static const IconData cloudUpload = LucideIcons.cloudUpload;

  // Status / feedback
  static const IconData success = LucideIcons.circleCheck;
  static const IconData error = LucideIcons.circleAlert;
  static const IconData info = LucideIcons.info;
  static const IconData loading = LucideIcons.loaderCircle;
  static const IconData stop = LucideIcons.circleStop;
  static const IconData circle = LucideIcons.circle;
  static const IconData radioOff = LucideIcons.circle;
  static const IconData radioOn = LucideIcons.circleDot;
  static const IconData star = LucideIcons.star;
  static const IconData notifications = LucideIcons.bellRing;
  static const IconData secure = LucideIcons.shieldCheck;
  static const IconData insecure = LucideIcons.shieldAlert;

  // Visibility
  static const IconData visible = LucideIcons.eye;
  static const IconData hidden = LucideIcons.eyeOff;
  static const IconData preview = LucideIcons.scanEye;
  static const IconData imageError = LucideIcons.imageOff;

  // Views / layout
  static const IconData sidebarToggle = LucideIcons.panelLeft;
  static const IconData gridView = LucideIcons.layoutGrid;
  static const IconData listView = LucideIcons.list;
  static const IconData outline = LucideIcons.tableOfContents;
  static const IconData tabUnselected = LucideIcons.appWindow;
  static const IconData tab = LucideIcons.arrowRightToLine;
  static const IconData square = LucideIcons.square;

  // Settings / tools
  static const IconData settings = LucideIcons.settings;
  static const IconData tune = LucideIcons.slidersHorizontal;
  static const IconData agent = LucideIcons.bot;
  static const IconData quota = LucideIcons.gauge;
  static const IconData resources = LucideIcons.activity;
  static const IconData profile = LucideIcons.circleUserRound;
  static const IconData devTools = LucideIcons.wrench;
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData terminal = LucideIcons.terminal;
  static const IconData code = LucideIcons.code;
  static const IconData keyboard = LucideIcons.keyboard;
  // Prompt composer: write/send a message into the active terminal.
  static const IconData composer = LucideIcons.messageSquarePlus;
  static const IconData ai = LucideIcons.sparkles;
  static const IconData package = LucideIcons.package;
  static const IconData public = LucideIcons.globe;
  static const IconData theme = LucideIcons.moon;
  static const IconData external = LucideIcons.externalLink;
  static const IconData text = LucideIcons.type;
}
