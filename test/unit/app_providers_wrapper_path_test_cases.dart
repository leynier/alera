part of 'app_providers_test.dart';

void _registerAppProvidersWrapperPathTests() {
  test('mergeTerminalLaunchEnvironment joins wrapper dirs with PATH list separator', () {
    final pathListSeparator = Platform.isWindows ? ';' : ':';
    final aleraShim = Platform.isWindows
        ? r'C:\alera\terminal_tools\bin'
        : '/alera/terminal_tools/bin';
    final ampWrapper = Platform.isWindows
        ? r'C:\alera\wrappers\session\bin'
        : '/alera/wrappers/session/bin';
    final target = <String, String>{
      'ALERA_RUNTIME_DIR': '/runtime',
      'ALERA_AGENT_WRAPPER_PATH': aleraShim,
    };

    mergeTerminalLaunchEnvironmentForTesting(target, <String, String>{
      'ALERA_AMP_CONFIG_DIR': '/overlay/amp',
      'ALERA_AGENT_WRAPPER_PATH': ampWrapper,
    });

    expect(
      target['ALERA_AGENT_WRAPPER_PATH'],
      '$aleraShim$pathListSeparator$ampWrapper',
    );
    expect(target['ALERA_AMP_CONFIG_DIR'], '/overlay/amp');
    expect(target['ALERA_RUNTIME_DIR'], '/runtime');

    // Merging again must not re-split absolute paths on filesystem separators.
    mergeTerminalLaunchEnvironmentForTesting(target, <String, String>{
      'ALERA_AGENT_WRAPPER_PATH': ampWrapper,
    });
    expect(
      target['ALERA_AGENT_WRAPPER_PATH'],
      '$aleraShim$pathListSeparator$ampWrapper',
    );
  });
}
