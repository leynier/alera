// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'agent_status.dart';

class AgentStatusStateMapper extends EnumMapper<AgentStatusState> {
  AgentStatusStateMapper._();

  static AgentStatusStateMapper? _instance;
  static AgentStatusStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentStatusStateMapper._());
    }
    return _instance!;
  }

  static AgentStatusState fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AgentStatusState decode(dynamic value) {
    switch (value) {
      case r'working':
        return AgentStatusState.working;
      case r'waiting':
        return AgentStatusState.waiting;
      case r'blocked':
        return AgentStatusState.blocked;
      case r'done':
        return AgentStatusState.done;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AgentStatusState self) {
    switch (self) {
      case AgentStatusState.working:
        return r'working';
      case AgentStatusState.waiting:
        return r'waiting';
      case AgentStatusState.blocked:
        return r'blocked';
      case AgentStatusState.done:
        return r'done';
    }
  }
}

extension AgentStatusStateMapperExtension on AgentStatusState {
  String toValue() {
    AgentStatusStateMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AgentStatusState>(this) as String;
  }
}

class AgentTypeMapper extends EnumMapper<AgentType> {
  AgentTypeMapper._();

  static AgentTypeMapper? _instance;
  static AgentTypeMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentTypeMapper._());
    }
    return _instance!;
  }

  static AgentType fromValue(dynamic value) {
    ensureInitialized();
    return MapperContainer.globals.fromValue(value);
  }

  @override
  AgentType decode(dynamic value) {
    switch (value) {
      case r'codex':
        return AgentType.codex;
      case r'claude':
        return AgentType.claude;
      case r'copilot':
        return AgentType.copilot;
      case r'cursor':
        return AgentType.cursor;
      case r'agy':
        return AgentType.agy;
      case r'opencode':
        return AgentType.opencode;
      case r'opencode2':
        return AgentType.opencode2;
      case r'pi':
        return AgentType.pi;
      case r'amp':
        return AgentType.amp;
      case r'grok':
        return AgentType.grok;
      case r'fx':
        return AgentType.fx;
      default:
        throw MapperException.unknownEnumValue(value);
    }
  }

  @override
  dynamic encode(AgentType self) {
    switch (self) {
      case AgentType.codex:
        return r'codex';
      case AgentType.claude:
        return r'claude';
      case AgentType.copilot:
        return r'copilot';
      case AgentType.cursor:
        return r'cursor';
      case AgentType.agy:
        return r'agy';
      case AgentType.opencode:
        return r'opencode';
      case AgentType.opencode2:
        return r'opencode2';
      case AgentType.pi:
        return r'pi';
      case AgentType.amp:
        return r'amp';
      case AgentType.grok:
        return r'grok';
      case AgentType.fx:
        return r'fx';
    }
  }
}

extension AgentTypeMapperExtension on AgentType {
  String toValue() {
    AgentTypeMapper.ensureInitialized();
    return MapperContainer.globals.toValue<AgentType>(this) as String;
  }
}

class AgentStatusEntryMapper extends ClassMapperBase<AgentStatusEntry> {
  AgentStatusEntryMapper._();

  static AgentStatusEntryMapper? _instance;
  static AgentStatusEntryMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = AgentStatusEntryMapper._());
      AgentTypeMapper.ensureInitialized();
      AgentStatusStateMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'AgentStatusEntry';

  static String _$terminalSessionId(AgentStatusEntry v) => v.terminalSessionId;
  static const Field<AgentStatusEntry, String> _f$terminalSessionId = Field(
    'terminalSessionId',
    _$terminalSessionId,
  );
  static String _$workspaceId(AgentStatusEntry v) => v.workspaceId;
  static const Field<AgentStatusEntry, String> _f$workspaceId = Field(
    'workspaceId',
    _$workspaceId,
  );
  static String _$tabId(AgentStatusEntry v) => v.tabId;
  static const Field<AgentStatusEntry, String> _f$tabId = Field(
    'tabId',
    _$tabId,
  );
  static AgentType _$agentType(AgentStatusEntry v) => v.agentType;
  static const Field<AgentStatusEntry, AgentType> _f$agentType = Field(
    'agentType',
    _$agentType,
  );
  static AgentStatusState _$state(AgentStatusEntry v) => v.state;
  static const Field<AgentStatusEntry, AgentStatusState> _f$state = Field(
    'state',
    _$state,
  );
  static String _$prompt(AgentStatusEntry v) => v.prompt;
  static const Field<AgentStatusEntry, String> _f$prompt = Field(
    'prompt',
    _$prompt,
  );
  static DateTime _$updatedAt(AgentStatusEntry v) => v.updatedAt;
  static const Field<AgentStatusEntry, DateTime> _f$updatedAt = Field(
    'updatedAt',
    _$updatedAt,
  );
  static DateTime _$stateStartedAt(AgentStatusEntry v) => v.stateStartedAt;
  static const Field<AgentStatusEntry, DateTime> _f$stateStartedAt = Field(
    'stateStartedAt',
    _$stateStartedAt,
  );
  static String? _$toolName(AgentStatusEntry v) => v.toolName;
  static const Field<AgentStatusEntry, String> _f$toolName = Field(
    'toolName',
    _$toolName,
    opt: true,
  );
  static String? _$toolInput(AgentStatusEntry v) => v.toolInput;
  static const Field<AgentStatusEntry, String> _f$toolInput = Field(
    'toolInput',
    _$toolInput,
    opt: true,
  );
  static String? _$lastAssistantMessage(AgentStatusEntry v) =>
      v.lastAssistantMessage;
  static const Field<AgentStatusEntry, String> _f$lastAssistantMessage = Field(
    'lastAssistantMessage',
    _$lastAssistantMessage,
    opt: true,
  );
  static bool? _$interrupted(AgentStatusEntry v) => v.interrupted;
  static const Field<AgentStatusEntry, bool> _f$interrupted = Field(
    'interrupted',
    _$interrupted,
    opt: true,
  );

  @override
  final MappableFields<AgentStatusEntry> fields = const {
    #terminalSessionId: _f$terminalSessionId,
    #workspaceId: _f$workspaceId,
    #tabId: _f$tabId,
    #agentType: _f$agentType,
    #state: _f$state,
    #prompt: _f$prompt,
    #updatedAt: _f$updatedAt,
    #stateStartedAt: _f$stateStartedAt,
    #toolName: _f$toolName,
    #toolInput: _f$toolInput,
    #lastAssistantMessage: _f$lastAssistantMessage,
    #interrupted: _f$interrupted,
  };

  static AgentStatusEntry _instantiate(DecodingData data) {
    return AgentStatusEntry(
      terminalSessionId: data.dec(_f$terminalSessionId),
      workspaceId: data.dec(_f$workspaceId),
      tabId: data.dec(_f$tabId),
      agentType: data.dec(_f$agentType),
      state: data.dec(_f$state),
      prompt: data.dec(_f$prompt),
      updatedAt: data.dec(_f$updatedAt),
      stateStartedAt: data.dec(_f$stateStartedAt),
      toolName: data.dec(_f$toolName),
      toolInput: data.dec(_f$toolInput),
      lastAssistantMessage: data.dec(_f$lastAssistantMessage),
      interrupted: data.dec(_f$interrupted),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static AgentStatusEntry fromMap(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<AgentStatusEntry>(map);
  }

  static AgentStatusEntry fromJson(String json) {
    return ensureInitialized().decodeJson<AgentStatusEntry>(json);
  }
}

mixin AgentStatusEntryMappable {
  String toJson() {
    return AgentStatusEntryMapper.ensureInitialized()
        .encodeJson<AgentStatusEntry>(this as AgentStatusEntry);
  }

  Map<String, dynamic> toMap() {
    return AgentStatusEntryMapper.ensureInitialized()
        .encodeMap<AgentStatusEntry>(this as AgentStatusEntry);
  }

  AgentStatusEntryCopyWith<AgentStatusEntry, AgentStatusEntry, AgentStatusEntry>
  get copyWith =>
      _AgentStatusEntryCopyWithImpl<AgentStatusEntry, AgentStatusEntry>(
        this as AgentStatusEntry,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return AgentStatusEntryMapper.ensureInitialized().stringifyValue(
      this as AgentStatusEntry,
    );
  }

  @override
  bool operator ==(Object other) {
    return AgentStatusEntryMapper.ensureInitialized().equalsValue(
      this as AgentStatusEntry,
      other,
    );
  }

  @override
  int get hashCode {
    return AgentStatusEntryMapper.ensureInitialized().hashValue(
      this as AgentStatusEntry,
    );
  }
}

extension AgentStatusEntryValueCopy<$R, $Out>
    on ObjectCopyWith<$R, AgentStatusEntry, $Out> {
  AgentStatusEntryCopyWith<$R, AgentStatusEntry, $Out>
  get $asAgentStatusEntry =>
      $base.as((v, t, t2) => _AgentStatusEntryCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class AgentStatusEntryCopyWith<$R, $In extends AgentStatusEntry, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? terminalSessionId,
    String? workspaceId,
    String? tabId,
    AgentType? agentType,
    AgentStatusState? state,
    String? prompt,
    DateTime? updatedAt,
    DateTime? stateStartedAt,
    String? toolName,
    String? toolInput,
    String? lastAssistantMessage,
    bool? interrupted,
  });
  AgentStatusEntryCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _AgentStatusEntryCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, AgentStatusEntry, $Out>
    implements AgentStatusEntryCopyWith<$R, AgentStatusEntry, $Out> {
  _AgentStatusEntryCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<AgentStatusEntry> $mapper =
      AgentStatusEntryMapper.ensureInitialized();
  @override
  $R call({
    String? terminalSessionId,
    String? workspaceId,
    String? tabId,
    AgentType? agentType,
    AgentStatusState? state,
    String? prompt,
    DateTime? updatedAt,
    DateTime? stateStartedAt,
    Object? toolName = $none,
    Object? toolInput = $none,
    Object? lastAssistantMessage = $none,
    Object? interrupted = $none,
  }) => $apply(
    FieldCopyWithData({
      if (terminalSessionId != null) #terminalSessionId: terminalSessionId,
      if (workspaceId != null) #workspaceId: workspaceId,
      if (tabId != null) #tabId: tabId,
      if (agentType != null) #agentType: agentType,
      if (state != null) #state: state,
      if (prompt != null) #prompt: prompt,
      if (updatedAt != null) #updatedAt: updatedAt,
      if (stateStartedAt != null) #stateStartedAt: stateStartedAt,
      if (toolName != $none) #toolName: toolName,
      if (toolInput != $none) #toolInput: toolInput,
      if (lastAssistantMessage != $none)
        #lastAssistantMessage: lastAssistantMessage,
      if (interrupted != $none) #interrupted: interrupted,
    }),
  );
  @override
  AgentStatusEntry $make(CopyWithData data) => AgentStatusEntry(
    terminalSessionId: data.get(
      #terminalSessionId,
      or: $value.terminalSessionId,
    ),
    workspaceId: data.get(#workspaceId, or: $value.workspaceId),
    tabId: data.get(#tabId, or: $value.tabId),
    agentType: data.get(#agentType, or: $value.agentType),
    state: data.get(#state, or: $value.state),
    prompt: data.get(#prompt, or: $value.prompt),
    updatedAt: data.get(#updatedAt, or: $value.updatedAt),
    stateStartedAt: data.get(#stateStartedAt, or: $value.stateStartedAt),
    toolName: data.get(#toolName, or: $value.toolName),
    toolInput: data.get(#toolInput, or: $value.toolInput),
    lastAssistantMessage: data.get(
      #lastAssistantMessage,
      or: $value.lastAssistantMessage,
    ),
    interrupted: data.get(#interrupted, or: $value.interrupted),
  );

  @override
  AgentStatusEntryCopyWith<$R2, AgentStatusEntry, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _AgentStatusEntryCopyWithImpl<$R2, $Out2>($value, $cast, t);
}
