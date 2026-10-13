import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';

const int defaultSshPort = 22;

/// What the user types as SSH Address: `user@host[:port]`, with an IPv6 host
/// in brackets when it carries a port (`user@[::1]:2222`).
class const SshAddress({
  required final String username,
  required final String host,
  final int port = defaultSshPort,
}) {
  factory fromTarget(SshTarget target) => SshAddress(
    username: target.username,
    host: target.host,
    port: target.port,
  );

  /// `user@host`, plus `:port` when it is not 22. An IPv6 host is bracketed
  /// only when a port follows, so the text parses back to the same address.
  String format() {
    if (port == defaultSshPort) {
      return '$username@$host';
    }
    final hostText = host.contains(':') ? '[$host]' : host;
    return '$username@$hostText:$port';
  }

  @override
  String toString() => format();
}

/// Parses an SSH Address. Throws a [FormatException] whose message is a
/// sentence the form can show as is.
SshAddress parseSshAddress(String text) {
  final value = text.trim();
  if (value.isEmpty) {
    throw const FormatException('Enter an SSH address such as user@host.');
  }
  if (value.contains(RegExp(r'\s'))) {
    throw const FormatException('The SSH address cannot contain spaces.');
  }
  final at = value.lastIndexOf('@');
  if (at < 0) {
    throw const FormatException('Include the username, as in user@host.');
  }
  final username = value.substring(0, at);
  if (username.isEmpty) {
    throw const FormatException('Include the username, as in user@host.');
  }
  final rest = value.substring(at + 1);
  final (host, portText) = _splitHostAndPort(rest);
  if (host.isEmpty) {
    throw const FormatException('Include the host, as in user@host.');
  }
  if (portText == null) {
    return SshAddress(username: username, host: host);
  }
  final port = int.tryParse(portText);
  if (port == null || port < 1 || port > 65535) {
    throw const FormatException('Port must be between 1 and 65535.');
  }
  return SshAddress(username: username, host: host, port: port);
}

SshAddress? tryParseSshAddress(String text) {
  try {
    return parseSshAddress(text);
  } on FormatException {
    return null;
  }
}

/// The message [parseSshAddress] would throw, or null for a valid address.
String? sshAddressError(String text) {
  try {
    parseSshAddress(text);
    return null;
  } on FormatException catch (error) {
    return error.message;
  }
}

/// `user@host` (+`:port` when not 22) for list rows and headers.
String sshAddressLabel(SshTarget target) =>
    SshAddress.fromTarget(target).format();

/// The ssh command that reaches [target] from a terminal, for Copy SSH
/// Command. A path with spaces is double-quoted, which every shell the hub
/// may run (POSIX shells, cmd and PowerShell) reads the same way.
String sshCommandFor(SshTarget target) {
  final parts = <String>['ssh'];
  if (target.port != defaultSshPort) {
    parts.addAll(<String>['-p', '${target.port}']);
  }
  final identityFile = target.identityFile?.trim();
  if (identityFile != null && identityFile.isNotEmpty) {
    parts.addAll(<String>['-i', _quoteIfNeeded(identityFile)]);
  }
  parts.add('${target.username}@${target.host}');
  return parts.join(' ');
}

(String, String?) _splitHostAndPort(String text) {
  if (text.startsWith('[')) {
    final close = text.indexOf(']');
    if (close < 0) {
      throw const FormatException('Close the IPv6 address with "]".');
    }
    final host = text.substring(1, close);
    final after = text.substring(close + 1);
    if (after.isEmpty) {
      return (host, null);
    }
    if (!after.startsWith(':')) {
      throw const FormatException(
        'Write the port after the host, as in user@host:22.',
      );
    }
    return (host, after.substring(1));
  }
  final colon = text.indexOf(':');
  if (colon < 0) {
    return (text, null);
  }
  // A bare IPv6 address has several colons and no port; brackets are needed
  // to add one.
  if (text.indexOf(':', colon + 1) >= 0) {
    return (text, null);
  }
  return (text.substring(0, colon), text.substring(colon + 1));
}

String _quoteIfNeeded(String value) {
  return value.contains(RegExp(r'\s')) ? '"$value"' : value;
}
