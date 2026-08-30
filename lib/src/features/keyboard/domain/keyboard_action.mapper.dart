// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'keyboard_action.dart';

class TerminalShortcutPolicyMapper extends EnumMapper<TerminalShortcutPolicy> {
  TerminalShortcutPolicyMapper._();

  static TerminalShortcutPolicyMapper? _instance;
  static TerminalShortcutPolicyMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = TerminalShortcutPolicyMapper._());
    }
    return _instance!;
  }

  static TerminalShortcutPolicy fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  TerminalShortcutPolicy decode(dynamic value) {
    switch (value) {
      case r'appFirst':
        return TerminalShortcutPolicy.appFirst;
      case r'terminalFirst':
        return TerminalShortcutPolicy.terminalFirst;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(TerminalShortcutPolicy self) {
    switch (self) {
      case TerminalShortcutPolicy.appFirst:
        return r'appFirst';
      case TerminalShortcutPolicy.terminalFirst:
        return r'terminalFirst';
    }
  }
}

extension TerminalShortcutPolicyMapperExtension on TerminalShortcutPolicy {
  String toValue() {
    TerminalShortcutPolicyMapper.ensureInitialized();
    return MapperContainer.globals.toValue<TerminalShortcutPolicy>(this)
        as String;
  }
}

class KeyboardActionIdMapper extends EnumMapper<KeyboardActionId> {
  KeyboardActionIdMapper._();

  static KeyboardActionIdMapper? _instance;
  static KeyboardActionIdMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = KeyboardActionIdMapper._());
    }
    return _instance!;
  }

  static KeyboardActionId fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  KeyboardActionId decode(dynamic value) {
    switch (value) {
      case r'openSettings':
        return KeyboardActionId.openSettings;
      case r'openAutomations':
        return KeyboardActionId.openAutomations;
      case r'openRunBoard':
        return KeyboardActionId.openRunBoard;
      case r'openQuickOpen':
        return KeyboardActionId.openQuickOpen;
      case r'openCommandPalette':
        return KeyboardActionId.openCommandPalette;
      case r'addProject':
        return KeyboardActionId.addProject;
      case r'toggleSidebar':
        return KeyboardActionId.toggleSidebar;
      case r'createWorkspace':
        return KeyboardActionId.createWorkspace;
      case r'navigateBack':
        return KeyboardActionId.navigateBack;
      case r'navigateForward':
        return KeyboardActionId.navigateForward;
      case r'findInFiles':
        return KeyboardActionId.findInFiles;
      case r'findInTerminal':
        return KeyboardActionId.findInTerminal;
      case r'toggleTerminalComposer':
        return KeyboardActionId.toggleTerminalComposer;
      case r'replaceInFiles':
        return KeyboardActionId.replaceInFiles;
      case r'saveFile':
        return KeyboardActionId.saveFile;
      case r'newTerminalTab':
        return KeyboardActionId.newTerminalTab;
      case r'newBrowserTab':
        return KeyboardActionId.newBrowserTab;
      case r'closeTab':
        return KeyboardActionId.closeTab;
      case r'nextTab':
        return KeyboardActionId.nextTab;
      case r'previousTab':
        return KeyboardActionId.previousTab;
      case r'goToTab1':
        return KeyboardActionId.goToTab1;
      case r'goToTab2':
        return KeyboardActionId.goToTab2;
      case r'goToTab3':
        return KeyboardActionId.goToTab3;
      case r'goToTab4':
        return KeyboardActionId.goToTab4;
      case r'goToTab5':
        return KeyboardActionId.goToTab5;
      case r'goToTab6':
        return KeyboardActionId.goToTab6;
      case r'goToTab7':
        return KeyboardActionId.goToTab7;
      case r'goToTab8':
        return KeyboardActionId.goToTab8;
      case r'goToTab9':
        return KeyboardActionId.goToTab9;
      case r'splitRight':
        return KeyboardActionId.splitRight;
      case r'splitDown':
        return KeyboardActionId.splitDown;
      case r'closeSplit':
        return KeyboardActionId.closeSplit;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(KeyboardActionId self) {
    switch (self) {
      case KeyboardActionId.openSettings:
        return r'openSettings';
      case KeyboardActionId.openAutomations:
        return r'openAutomations';
      case KeyboardActionId.openRunBoard:
        return r'openRunBoard';
      case KeyboardActionId.openQuickOpen:
        return r'openQuickOpen';
      case KeyboardActionId.openCommandPalette:
        return r'openCommandPalette';
      case KeyboardActionId.addProject:
        return r'addProject';
      case KeyboardActionId.toggleSidebar:
        return r'toggleSidebar';
      case KeyboardActionId.createWorkspace:
        return r'createWorkspace';
      case KeyboardActionId.navigateBack:
        return r'navigateBack';
      case KeyboardActionId.navigateForward:
        return r'navigateForward';
      case KeyboardActionId.findInFiles:
        return r'findInFiles';
      case KeyboardActionId.findInTerminal:
        return r'findInTerminal';
      case KeyboardActionId.toggleTerminalComposer:
        return r'toggleTerminalComposer';
      case KeyboardActionId.replaceInFiles:
        return r'replaceInFiles';
      case KeyboardActionId.saveFile:
        return r'saveFile';
      case KeyboardActionId.newTerminalTab:
        return r'newTerminalTab';
      case KeyboardActionId.newBrowserTab:
        return r'newBrowserTab';
      case KeyboardActionId.closeTab:
        return r'closeTab';
      case KeyboardActionId.nextTab:
        return r'nextTab';
      case KeyboardActionId.previousTab:
        return r'previousTab';
      case KeyboardActionId.goToTab1:
        return r'goToTab1';
      case KeyboardActionId.goToTab2:
        return r'goToTab2';
      case KeyboardActionId.goToTab3:
        return r'goToTab3';
      case KeyboardActionId.goToTab4:
        return r'goToTab4';
      case KeyboardActionId.goToTab5:
        return r'goToTab5';
      case KeyboardActionId.goToTab6:
        return r'goToTab6';
      case KeyboardActionId.goToTab7:
        return r'goToTab7';
      case KeyboardActionId.goToTab8:
        return r'goToTab8';
      case KeyboardActionId.goToTab9:
        return r'goToTab9';
      case KeyboardActionId.splitRight:
        return r'splitRight';
      case KeyboardActionId.splitDown:
        return r'splitDown';
      case KeyboardActionId.closeSplit:
        return r'closeSplit';
    }
  }
}

extension KeyboardActionIdMapperExtension on KeyboardActionId {
  String toValue() {
    KeyboardActionIdMapper.ensureInitialized();
    return MapperContainer.globals.toValue<KeyboardActionId>(this) as String;
  }
}
