enum AgentChatTitleSource {
  defaultLabel,
  derived,
  user;

  String get wire => this == defaultLabel ? 'default' : name;

  static AgentChatTitleSource fromJson(Object? value) => switch (value) {
    'derived' => derived,
    'user' => user,
    _ => defaultLabel,
  };
}
