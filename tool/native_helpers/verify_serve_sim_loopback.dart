import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  try {
    final options = _Options.parse(args);
    final port = options.port ?? await _reserveIpv6LoopbackPort();
    final helper = await Process.start(options.helperPath, <String>[
      options.deviceUdid,
      '--port',
      '$port',
    ]);
    final output = StringBuffer();
    final stdoutDone = _capture(helper.stdout, output);
    final stderrDone = _capture(helper.stderr, output);
    try {
      await _waitForHealthyLoopback(helper, port, output);
      await _verifyListenerAddress(helper.pid, port);
      await _expectConnectionRefused(.loopbackIPv4, port);

      final lanAddresses = options.lanAddress == null
          ? await _discoverLanAddresses()
          : <InternetAddress>[InternetAddress(options.lanAddress!)];
      if (lanAddresses.isEmpty) {
        throw StateError(
          'No non-loopback address is available for the LAN isolation test.',
        );
      }
      for (final address in lanAddresses) {
        await _expectConnectionRefused(address, port);
      }
      stdout.writeln(
        'Verified serve-sim on [::1]:$port; IPv4 loopback and '
        '${lanAddresses.map((address) => address.address).join(', ')} '
        'cannot connect.',
      );
    } finally {
      helper.kill(.sigterm);
      try {
        await helper.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        helper.kill(.sigkill);
        await helper.exitCode;
      }
      await Future.wait<void>(<Future<void>>[stdoutDone, stderrDone]);
      if (output.isNotEmpty) {
        stdout.write(output);
      }
    }
  } catch (error) {
    stderr.writeln('serve-sim loopback verification failed: $error');
    exitCode = 1;
  }
}

Future<void> _capture(Stream<List<int>> stream, StringBuffer output) async {
  await for (final text in stream.transform(utf8.decoder)) {
    output.write(text);
  }
}

Future<int> _reserveIpv6LoopbackPort() async {
  final socket = await ServerSocket.bind(
    InternetAddress.loopbackIPv6,
    0,
    v6Only: true,
  );
  final port = socket.port;
  await socket.close();
  return port;
}

Future<void> _waitForHealthyLoopback(
  Process helper,
  int port,
  StringBuffer output,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    final helperExit = await _completedExitCode(helper);
    if (helperExit != null) {
      throw StateError(
        'serve-sim exited with $helperExit before becoming healthy.\n$output',
      );
    }
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(milliseconds: 500);
    try {
      final request = await client.getUrl(
        Uri(scheme: 'http', host: '::1', port: port, path: '/health'),
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.ok &&
          (jsonDecode(body) as Map<String, Object?>)['status'] == 'ok') {
        return;
      }
    } catch (_) {
      await Future.pause(const Duration(milliseconds: 150));
    } finally {
      client.close(force: true);
    }
  }
  throw StateError('serve-sim did not become healthy on [::1]:$port.\n$output');
}

Future<int?> _completedExitCode(Process process) async {
  try {
    return await process.exitCode.timeout(.zero);
  } on TimeoutException {
    return null;
  }
}

Future<void> _verifyListenerAddress(int pid, int port) async {
  final lsof = await Process.run('/usr/sbin/lsof', <String>[
    '-nP',
    '-a',
    '-p',
    '$pid',
    '-iTCP:$port',
    '-sTCP:LISTEN',
  ]);
  if (lsof.exitCode != 0) {
    throw ProcessException(
      '/usr/sbin/lsof',
      <String>['-nP', '-a', '-p', '$pid', '-iTCP:$port', '-sTCP:LISTEN'],
      '${lsof.stdout}\n${lsof.stderr}',
      lsof.exitCode,
    );
  }
  final listeners = '${lsof.stdout}';
  if (!listeners.contains('[::1]:$port') ||
      listeners.contains('*:$port') ||
      listeners.contains('[::]:$port')) {
    throw StateError(
      'serve-sim listener is not restricted to [::1]:$port:\n$listeners',
    );
  }
}

Future<void> _expectConnectionRefused(InternetAddress address, int port) async {
  Socket? socket;
  try {
    socket = await Socket.connect(
      address,
      port,
      timeout: const Duration(seconds: 2),
    );
  } on SocketException {
    return;
  } on TimeoutException {
    return;
  } finally {
    await socket?.close();
  }
  throw StateError('serve-sim unexpectedly accepted ${address.address}:$port.');
}

Future<List<InternetAddress>> _discoverLanAddresses() async {
  final interfaces = await NetworkInterface.list(
    includeLoopback: false,
    type: .IPv4,
  );
  return <InternetAddress>[
    for (final interface in interfaces)
      for (final address in interface.addresses)
        if (!address.isLoopback && !address.isLinkLocal) address,
  ];
}

final class _Options({
  required final String helperPath,
  required final String deviceUdid,
  required final int? port,
  required final String? lanAddress,
}) {
  factory parse(List<String> args) {
    final values = <String, String>{};
    for (var index = 0; index < args.length; index += 2) {
      if (index + 1 >= args.length || !args[index].startsWith('--')) {
        throw const FormatException('Arguments must be --name value pairs.');
      }
      values[args[index]] = args[index + 1];
    }
    final helper = values['--helper'];
    final device = values['--device'];
    if (helper == null || helper.isEmpty || device == null || device.isEmpty) {
      throw const FormatException('--helper and --device are required.');
    }
    final rawPort = values['--port'];
    final port = rawPort == null ? null : int.tryParse(rawPort);
    if (rawPort != null && (port == null || port <= 0 || port > 65535)) {
      throw FormatException('Invalid --port: $rawPort');
    }
    return _Options(
      helperPath: helper,
      deviceUdid: device,
      port: port,
      lanAddress: values['--lan-address'],
    );
  }
}
