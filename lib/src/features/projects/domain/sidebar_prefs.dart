import 'package:alera/src/app/theme/alera_tokens.dart';

class SidebarPrefs {
  const SidebarPrefs({
    required this.pinnedChatIds,
    required this.pinnedChatOrder,
    required this.collapsed,
    required this.width,
  });

  final Set<String> pinnedChatIds;
  final List<String> pinnedChatOrder;
  final bool collapsed;
  final double width;

  static const SidebarPrefs defaults = SidebarPrefs(
    pinnedChatIds: <String>{},
    pinnedChatOrder: <String>[],
    collapsed: false,
    width: AleraTokens.sidebarDefaultWidth,
  );

  SidebarPrefs copyWith({
    Set<String>? pinnedChatIds,
    List<String>? pinnedChatOrder,
    bool? collapsed,
    double? width,
  }) {
    return SidebarPrefs(
      pinnedChatIds: pinnedChatIds ?? this.pinnedChatIds,
      pinnedChatOrder: pinnedChatOrder ?? this.pinnedChatOrder,
      collapsed: collapsed ?? this.collapsed,
      width: width ?? this.width,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'pinnedChatIds': pinnedChatIds.toList(growable: false),
      'pinnedChatOrder': pinnedChatOrder,
      'collapsed': collapsed,
      'width': width,
    };
  }

  factory SidebarPrefs.fromJson(Map<String, Object?> json) {
    final pinnedRaw = json['pinnedChatIds'];
    final orderRaw = json['pinnedChatOrder'];
    final collapsedRaw = json['collapsed'];
    final widthRaw = json['width'];
    final pinned = <String>{
      if (pinnedRaw is List)
        for (final id in pinnedRaw)
          if (id is String && id.isNotEmpty) id,
    };
    final order = <String>[
      if (orderRaw is List)
        for (final id in orderRaw)
          if (id is String && id.isNotEmpty && pinned.contains(id)) id,
    ];
    // Append any pinned ids missing from the stored order to preserve them.
    for (final id in pinned) {
      if (!order.contains(id)) {
        order.add(id);
      }
    }
    final collapsed = collapsedRaw is bool ? collapsedRaw : false;
    final rawWidth = widthRaw is num
        ? widthRaw.toDouble()
        : AleraTokens.sidebarDefaultWidth;
    final width = rawWidth.clamp(
      AleraTokens.sidebarMinWidth,
      AleraTokens.sidebarMaxWidth,
    );
    return SidebarPrefs(
      pinnedChatIds: pinned,
      pinnedChatOrder: order,
      collapsed: collapsed,
      width: width,
    );
  }
}
