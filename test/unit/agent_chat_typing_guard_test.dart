import 'package:alera/src/features/agent_chat/presentation/agent_chat_typing_guard.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Fixture {
  _Fixture() {
    guard = AgentChatTypingGuard(
      text: text,
      focus: focus,
      onRelease: releases.add,
      clock: () => now,
    );
  }

  final TextEditingController text = TextEditingController();
  final _FakeFocusNode focus = _FakeFocusNode();
  final List<AgentChatTypingRelease> releases = <AgentChatTypingRelease>[];
  DateTime now = DateTime.utc(2026, 10, 12, 10);
  late final AgentChatTypingGuard guard;

  void type(String value) => text.text = value;

  void elapse(FakeAsync async, Duration duration) {
    now = now.add(duration);
    async.elapse(duration);
  }

  void dispose() {
    guard.dispose();
    text.dispose();
    focus.dispose();
  }
}

/// A focus node whose focus the test sets directly.
final class _FakeFocusNode extends FocusNode {
  bool _focused = false;

  @override
  bool get hasFocus => _focused;

  set focused(bool value) {
    _focused = value;
    notifyListeners();
  }
}

void main() {
  test('nothing is held when the composer is idle', () {
    final fixture = _Fixture();
    fixture.focus.focused = true;
    expect(fixture.guard.hold(), isFalse);
    fixture.dispose();
  });

  test('a guard created in a focused composer assumes recent typing', () {
    fakeAsync((async) {
      final text = TextEditingController();
      final focus = _FakeFocusNode()..focused = true;
      final releases = <AgentChatTypingRelease>[];
      var now = DateTime.utc(2026, 10, 12, 10);
      final guard = AgentChatTypingGuard(
        text: text,
        focus: focus,
        onRelease: releases.add,
        clock: () => now,
      );
      expect(guard.hold(), isTrue);
      now = now.add(agentChatTypingIdle);
      async.elapse(agentChatTypingIdle);
      expect(releases, <AgentChatTypingRelease>[AgentChatTypingRelease.idle]);
      guard.dispose();
      text.dispose();
      focus.dispose();
    });
  });

  test('typing holds the takeover until a pause', () {
    fakeAsync((async) {
      final fixture = _Fixture();
      fixture.focus.focused = true;
      fixture.type('hel');
      expect(fixture.guard.hold(), isTrue);

      fixture.elapse(async, const Duration(milliseconds: 1000));
      fixture.type('hello');
      fixture.elapse(async, const Duration(milliseconds: 1000));
      expect(fixture.releases, isEmpty);

      fixture.elapse(async, agentChatTypingIdle);
      expect(fixture.releases, <AgentChatTypingRelease>[
        AgentChatTypingRelease.idle,
      ]);
      expect(fixture.text.text, 'hello');
      fixture.dispose();
    });
  });

  test('a send or a blur releases at once', () {
    fakeAsync((async) {
      final fixture = _Fixture();
      fixture.focus.focused = true;
      fixture.type('draft');
      expect(fixture.guard.hold(), isTrue);
      fixture.type('');
      expect(fixture.releases, <AgentChatTypingRelease>[
        AgentChatTypingRelease.sent,
      ]);

      fixture.type('again');
      expect(fixture.guard.hold(), isTrue);
      fixture.focus.focused = false;
      expect(fixture.releases.last, AgentChatTypingRelease.blurred);
      fixture.dispose();
    });
  });
}
