import 'dart:async';

import 'package:alera_agent_chat/src/agent_chat_provider_skill.dart';
import 'package:alera_agent_chat/src/agent_chat_transport.dart';

/// How long an answer stays current before the next menu asks again. The
/// runtime keeps its own five-minute discovery cache, so asking is cheap;
/// this only spares a request per keystroke.
const Duration agentChatSkillsFreshness = Duration(seconds: 30);

/// The skills of one chat, for its composer menus and its message chips.
/// [request] asks the runtime when the last answer is older than
/// [freshness], keeping the previous list while the new one loads, so the
/// menu never empties under the person typing.
///
/// It is plain Dart so the desktop and the phone share it; listeners hear
/// every change, as with a Flutter `ChangeNotifier`.
class AgentChatSkillsLoader {
  AgentChatSkillsLoader(
    this._load, {
    this.freshness = agentChatSkillsFreshness,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<AgentChatSkillList> Function({required bool refresh}) _load;
  final Duration freshness;
  final DateTime Function() _clock;
  final List<void Function()> _listeners = <void Function()>[];

  AgentChatSkillList? _list;
  DateTime? _loadedAt;
  Future<void>? _inFlight;
  Object? _error;
  bool _unsupported = false;
  bool _disposed = false;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    if (_disposed) return;
    for (final listener in List<void Function()>.of(_listeners)) {
      listener();
    }
  }

  /// The last answer, or `null` before the first one.
  AgentChatSkillList? get list => _list;

  /// The skills of the last answer, empty before one.
  List<AgentChatProviderSkill> get skills =>
      _list?.skills ?? const <AgentChatProviderSkill>[];

  bool get loading => _inFlight != null;

  /// Why the last request failed, when it did.
  Object? get error => _error;

  /// The runtime does not serve skills (`agentChatSkillsV1`).
  bool get unsupported => _unsupported;

  /// Loads the skills unless the last answer is still fresh or a request
  /// is already running.
  Future<void> request() {
    final loadedAt = _loadedAt;
    if (_unsupported || _disposed) return Future<void>.value();
    if (loadedAt != null && _clock().difference(loadedAt) < freshness) {
      return _inFlight ?? Future<void>.value();
    }
    return _start(refresh: false);
  }

  /// Asks the runtime to discover the skills again, bypassing its cache.
  Future<void> refresh() =>
      _unsupported || _disposed ? Future<void>.value() : _start(refresh: true);

  /// Forgets the answer, as when the chat switches agents.
  void reset() {
    if (_list == null && _loadedAt == null && _error == null) return;
    _list = null;
    _loadedAt = null;
    _error = null;
    _notify();
  }

  Future<void> _start({required bool refresh}) {
    final running = _inFlight;
    if (running != null) return running;
    final future = _run(refresh: refresh);
    _inFlight = future;
    _notify();
    return future;
  }

  Future<void> _run({required bool refresh}) async {
    try {
      final list = await _load(refresh: refresh);
      _list = list;
      _error = null;
      _loadedAt = _clock();
    } on AgentChatCapabilityRequired {
      _unsupported = true;
      _list = null;
    } on Object catch (error) {
      _error = error;
      _loadedAt = null;
    } finally {
      _inFlight = null;
      _notify();
    }
  }

  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}
