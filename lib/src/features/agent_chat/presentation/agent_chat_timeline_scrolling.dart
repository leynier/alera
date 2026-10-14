import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_timeline_sessions.dart';
import 'package:flutter/material.dart';

/// The three scroll behaviors of a chat timeline (following, anchoring a sent
/// prompt, free) and the save and restore of the reader's place in the
/// chat's session, so a tab switch puts them back where they were.
///
/// Any scroll the timeline did not make itself is the reader's: within
/// [AleraTokens.agentChatFollowRearmExtent] of the end it follows again,
/// anywhere else it frees the timeline.
mixin AgentChatTimelineScrolling<T extends StatefulWidget> on State<T> {
  final ScrollController scroll = ScrollController();
  final GlobalKey viewportKey = GlobalKey();

  /// Whether the end is out of view; drives the Scroll To End pill alone, so
  /// scrolling never rebuilds the rows.
  final ValueNotifier<bool> showScrollToEnd = ValueNotifier<bool>(false);

  /// Room added below the last entry while anchoring, so a just-sent prompt
  /// can sit near the top even before the answer fills the viewport.
  final ValueNotifier<double> anchorSpacer = ValueNotifier<double>(0);

  bool _settleScheduled = false;
  bool _placeScheduled = false;
  int _programmatic = 0;

  AgentChatTimelineSession get session;

  /// The laid-out box of the timeline entry with [key], if it is built.
  RenderBox? entryBox(String key);

  /// Keys of the entries built right now, for capturing the reader's place.
  Iterable<String> get builtEntryKeys;

  void initScrolling() {
    scroll.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => restoreScrolling());
  }

  /// Saves the scroll offset and mode. Safe while the timeline is being
  /// torn down, because it reads no layout: the entry under the reader is
  /// recorded by [recordReaderPlace] when scrolling settles instead.
  void saveScrolling() {
    if (!scroll.hasClients) return;
    session.pixels = scroll.position.pixels;
  }

  /// Records which entry sits at the top of the viewport, for a later
  /// restore. Called when scrolling settles. A scroll the timeline made
  /// itself (following, anchoring, restoring) is not the reader's place, and
  /// recording it mid-restore would replace the place being restored.
  void recordReaderPlace() {
    if (_programmatic > 0 || !mounted || !scroll.hasClients) return;
    session.pixels = scroll.position.pixels;
    if (_placeScheduled) return;
    _placeScheduled = true;
    // The notification arrives before the frame that lays out the last
    // scroll delta, so the entries' positions are only current after it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _placeScheduled = false;
      if (!mounted || !scroll.hasClients) return;
      if (session.mode != AgentChatScrollMode.free) {
        session.anchorKey = null;
        return;
      }
      session.pixels = scroll.position.pixels;
      final anchor = captureAnchor();
      session
        ..anchorKey = anchor?.key
        ..anchorOffset = anchor?.top ?? 0;
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void disposeScrolling() {
    scroll
      ..removeListener(_handleScroll)
      ..dispose();
    showScrollToEnd.dispose();
    anchorSpacer.dispose();
  }

  void _handleScroll() {
    if (!scroll.hasClients) return;
    final after = scroll.position.extentAfter;
    showScrollToEnd.value = after > AleraTokens.space48;
    if (_programmatic > 0) return;
    session.mode = after <= AleraTokens.agentChatFollowRearmExtent
        ? AgentChatScrollMode.following
        : AgentChatScrollMode.free;
    session
      ..anchoredEntryKey = null
      ..anchoredClientMessageId = null;
    anchorSpacer.value = 0;
  }

  void _jump(double target) {
    final position = scroll.position;
    final clamped = target.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() < 0.5) return;
    _programmatic += 1;
    try {
      scroll.jumpTo(clamped);
    } finally {
      _programmatic -= 1;
    }
  }

  /// Applies the session's mode after new output: follow to the end, keep
  /// the anchored prompt near the top, or leave the reader alone.
  void applyScrollMode() {
    switch (session.mode) {
      case AgentChatScrollMode.following:
        followToEnd();
      case AgentChatScrollMode.anchoring:
        _settle(_anchorStep);
      case AgentChatScrollMode.free:
        break;
    }
  }

  /// Pins [entryKey] near the top until tool activity starts or the reader
  /// scrolls.
  void startAnchoring(String entryKey, {String? clientMessageId}) {
    session
      ..mode = AgentChatScrollMode.anchoring
      ..anchoredEntryKey = entryKey
      ..anchoredClientMessageId = clientMessageId;
    _settle(_anchorStep);
  }

  void stopAnchoring() {
    session
      ..mode = AgentChatScrollMode.following
      ..anchoredEntryKey = null
      ..anchoredClientMessageId = null;
    anchorSpacer.value = 0;
    followToEnd();
  }

  /// Jumps to the end and follows again, as the pill does.
  void followToEnd({bool animate = false}) {
    session.mode = AgentChatScrollMode.following;
    if (animate && scroll.hasClients) {
      _programmatic += 1;
      unawaited(
        scroll
            .animateTo(
              scroll.position.maxScrollExtent,
              duration: AleraTokens.durationMid,
              curve: Curves.easeOut,
            )
            .whenComplete(() {
              _programmatic -= 1;
              if (mounted) _settle(_endStep);
            }),
      );
      return;
    }
    _settle(_endStep);
  }

  bool _endStep() {
    final position = scroll.position;
    if (position.extentAfter < AleraTokens.dividerExtent) return true;
    _jump(position.maxScrollExtent);
    return false;
  }

  bool _anchorStep() {
    final key = session.anchoredEntryKey;
    if (key == null) return true;
    final box = entryBox(key);
    final viewport = _viewportBox();
    if (viewport == null) return true;
    if (box == null) {
      // A just-sent prompt is the last entry; jumping to the end builds it.
      _jump(scroll.position.maxScrollExtent);
      return false;
    }
    final top =
        box.localToGlobal(Offset.zero).dy -
        viewport.localToGlobal(Offset.zero).dy;
    final position = scroll.position;
    final before = position.pixels;
    final desired = before + top - AleraTokens.space24;
    final max = position.maxScrollExtent;
    if (desired > max + 0.5) {
      // Not enough below the prompt yet: grow the spacer and retry once it
      // has laid out.
      anchorSpacer.value += desired - max;
      return false;
    }
    // As the answer grows the spacer is needed less; give back the slack.
    final slack = max - desired;
    if (slack > 0.5 && anchorSpacer.value > 0) {
      anchorSpacer.value = (anchorSpacer.value - slack).clamp(
        0,
        anchorSpacer.value,
      );
    }
    _jump(desired);
    return (scroll.position.pixels - before).abs() < 0.5;
  }

  /// Lazily built rows change the scroll extent as they lay out, so one step
  /// can land short; repeat over a few frames until [step] reports done.
  void _settle(bool Function() step) {
    if (_settleScheduled) return;
    _settleScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        for (var attempt = 0; attempt < 4; attempt += 1) {
          if (!mounted || !scroll.hasClients) return;
          if (step()) return;
          await WidgetsBinding.instance.endOfFrame;
        }
      } finally {
        _settleScheduled = false;
      }
    });
    // Called from a post-frame callback, nothing else may ask for the frame
    // this waits on.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Puts the reader back where the session says they were.
  void restoreScrolling() {
    if (!mounted || !scroll.hasClients) return;
    switch (session.mode) {
      case AgentChatScrollMode.following:
        followToEnd();
      case AgentChatScrollMode.anchoring:
        _settle(_anchorStep);
      case AgentChatScrollMode.free:
        final pixels = session.pixels;
        final key = session.anchorKey;
        // The lazily built list only knows its extent near what it has laid
        // out, so jump to the saved offset, then settle on the saved entry
        // once it is built.
        _settle(() {
          if (key != null && entryBox(key) != null) {
            restoreAnchor((key: key, top: session.anchorOffset));
            return true;
          }
          if (pixels != null) _jump(pixels);
          return key == null;
        });
    }
  }

  RenderBox? _viewportBox() {
    final box = viewportKey.currentContext?.findRenderObject() as RenderBox?;
    return box == null || !box.attached || !box.hasSize ? null : box;
  }

  /// The topmost visible entry and its top relative to the viewport top.
  ({String key, double top})? captureAnchor() {
    final viewport = _viewportBox();
    if (viewport == null) return null;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewport.size.height;
    ({String key, double top})? best;
    for (final key in builtEntryKeys) {
      final box = entryBox(key);
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top >= viewportBottom || top + box.size.height <= viewportTop) {
        continue;
      }
      final relative = top - viewportTop;
      if (best == null || relative < best.top) {
        best = (key: key, top: relative);
      }
    }
    return best;
  }

  /// Moves the timeline so the entry of [anchor] sits where it was captured.
  void restoreAnchor(({String key, double top}) anchor) {
    if (!mounted || !scroll.hasClients) return;
    final box = entryBox(anchor.key);
    final viewport = _viewportBox();
    if (box == null || viewport == null) return;
    final top =
        box.localToGlobal(Offset.zero).dy -
        viewport.localToGlobal(Offset.zero).dy;
    _jump(scroll.position.pixels + top - anchor.top);
  }
}
