import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Semantic icon registry for the mobile companion. Glyphs match the desktop
/// `AleraIcons` set (Lucide) so workspace rows stay visually consistent.
abstract final class AleraIcons {
  const AleraIcons._();

  static const IconData close = LucideIcons.x;
  static const IconData more = LucideIcons.ellipsisVertical;
  static const IconData chevronUp = LucideIcons.chevronUp;
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData pin = LucideIcons.pin;
  static const IconData pinOff = LucideIcons.pinOff;
  static const IconData folderSpecial = LucideIcons.folderGit2;
  static const IconData tag = LucideIcons.tag;
  static const IconData workspaceMain = LucideIcons.home;
  static const IconData workspaceChildren = LucideIcons.workflow;
  static const IconData gitBranch = LucideIcons.gitBranch;
  static const IconData success = LucideIcons.circleCheck;
  static const IconData check = LucideIcons.check;
  static const IconData notifications = LucideIcons.bell;
  static const IconData cancel = LucideIcons.circleX;
  static const IconData sync = LucideIcons.refreshCw;
  static const IconData search = LucideIcons.search;
  static const IconData tune = LucideIcons.slidersHorizontal;
  static const IconData settings = LucideIcons.settings;
  static const IconData add = LucideIcons.plus;
  static const IconData edit = LucideIcons.pencil;
  static const IconData delete = LucideIcons.trash2;
  static const IconData copy = LucideIcons.copy;
  static const IconData paste = LucideIcons.clipboard;
  static const IconData refresh = LucideIcons.refreshCw;
  static const IconData loading = LucideIcons.loaderCircle;
  static const IconData link = LucideIcons.link;
  static const IconData external = LucideIcons.externalLink;
  static const IconData theme = LucideIcons.moon;
  static const IconData workspaces = LucideIcons.folders;
  static const IconData listView = LucideIcons.list;
  static const IconData viewImage = LucideIcons.image;
  static const IconData folder = LucideIcons.folder;
  static const IconData folderOpen = LucideIcons.folderOpen;
  static const IconData cloudOff = LucideIcons.cloudOff;
  static const IconData systemUpdate = LucideIcons.download;
}
