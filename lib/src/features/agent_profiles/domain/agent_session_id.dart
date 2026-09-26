/// Mirrors the host's native session ID validation across CLI adapters.
bool isUsableAgentSessionId(String value) {
  final id = value.trim();
  return id.isNotEmpty &&
      !id.startsWith('-') &&
      !RegExp(r'''[\s\x00-\x1f\x7f-\x9f|&;<>$`()"'%!^]''').hasMatch(id);
}
