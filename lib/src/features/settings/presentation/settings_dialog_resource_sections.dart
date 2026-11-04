import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_settings_section.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_hosts_settings_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/agent_profiles_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/mobile_devices_pane.dart';
import 'package:alera/src/features/settings/presentation/panes/projects_pane.dart';
import 'package:alera/src/features/settings/presentation/settings_search_entries_resources.dart';
import 'package:alera/src/features/settings/presentation/settings_sections.dart';
import 'package:flutter/material.dart';

const List<SettingsGroupSpec> mobileDeviceGroups = <SettingsGroupSpec>[
  SettingsGroupSpec(id: 'gateway', title: 'Mobile Gateway'),
  SettingsGroupSpec(id: 'pairing', title: 'Link A Device'),
  SettingsGroupSpec(id: 'offers', title: 'Active Pairing Offers'),
  SettingsGroupSpec(id: 'devices', title: 'Paired Devices'),
];

/// The master-detail panes that manage declared entities: projects, mobile
/// devices, remote hosts, agent profiles and Agent Chat providers.
/// [initialProjectId], [initialHostId] and [initialProviderInstanceId] open
/// their pane on that entry; Providers also opens on [initialHostId].
List<SettingsSectionData> settingsResourceSections({
  required Map<String, GlobalKey> Function(String, List<SettingsGroupSpec>)
  paneKeys,
  String? initialProjectId,
  String? initialHostId,
  String? initialProviderInstanceId,
}) {
  return <SettingsSectionData>[
    SettingsSectionData(
      id: 'projects',
      title: 'Projects',
      description: 'Per-project workspace setup.',
      icon: AleraIcons.folderSpecial,
      entries: projectSearchEntries,
      navGroup: .resources,
      builder: (_) => ProjectSettingsPane(initialProjectId: initialProjectId),
    ),
    SettingsSectionData(
      id: 'mobileDevices',
      title: 'Mobile Devices',
      description: 'Pair and manage the mobile companion app.',
      icon: AleraIcons.mobileDevice,
      entries: mobileDeviceSearchEntries,
      groups: mobileDeviceGroups,
      navGroup: .resources,
      builder: (_) => MobileDevicesSettingsPane(
        groupKeys: paneKeys('mobileDevices', mobileDeviceGroups),
      ),
    ),
    SettingsSectionData(
      id: 'remoteHosts',
      title: 'Remote Hosts',
      description: 'Run workspaces on other machines over SSH. Alera installs and updates its runtime there.',
      icon: AleraIcons.host,
      entries: remoteHostSearchEntries,
      navGroup: .resources,
      builder: (_) => RemoteHostsSettingsPane(initialHostId: initialHostId),
    ),
    SettingsSectionData(
      id: 'agentProfiles',
      title: 'Agent Profiles',
      description: 'Launch configurations orchestration can dispatch to.',
      icon: AleraIcons.agent,
      entries: agentProfileSearchEntries,
      navGroup: .resources,
      builder: (_) => const AgentProfilesSettingsPane(),
    ),
    agentProviderSettingsSection(
      initialHostId: initialHostId,
      initialProviderInstanceId: initialProviderInstanceId,
    ),
  ];
}
