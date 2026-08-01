import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/projects/application/projects_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RemoteDirectoryPickerScreen extends ConsumerWidget {
  const RemoteDirectoryPickerScreen({
    super.key,
    required this.hostId,
    required this.actionLabel,
  });

  final String hostId;
  final String actionLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(hostDirectoryBrowserControllerProvider(hostId));
    return Scaffold(
      appBar: AppBar(title: const Text('Choose Folder')),
      body: SafeArea(
        child: switch (state) {
          AsyncData(value: final data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _PathHeader(
                path: data.listing?.path,
                onUp: data.listing == null
                    ? null
                    : () {
                        final parent = data.listing!.parentPath;
                        if (parent == null) {
                          ref
                              .read(
                                hostDirectoryBrowserControllerProvider(
                                  hostId,
                                ).notifier,
                              )
                              .showRoots();
                        } else {
                          ref
                              .read(
                                hostDirectoryBrowserControllerProvider(
                                  hostId,
                                ).notifier,
                              )
                              .open(parent);
                        }
                      },
              ),
              Expanded(
                child: data.listing == null
                    ? ListView(
                        children: <Widget>[
                          for (final root in data.roots)
                            ListTile(
                              leading: const Icon(Icons.storage_outlined),
                              title: Text(root.name),
                              subtitle: Text(
                                root.path,
                                style: const TextStyle(
                                  fontFamily: AleraTokens.monoFontFamily,
                                ),
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => ref
                                  .read(
                                    hostDirectoryBrowserControllerProvider(
                                      hostId,
                                    ).notifier,
                                  )
                                  .open(root.path),
                            ),
                        ],
                      )
                    : data.listing!.entries.isEmpty
                    ? const Center(child: Text('No subfolders'))
                    : ListView.builder(
                        itemCount: data.listing!.entries.length,
                        itemBuilder: (context, index) {
                          final entry = data.listing!.entries[index];
                          return ListTile(
                            leading: Icon(
                              entry.isSymlink
                                  ? Icons.drive_file_move_outline
                                  : Icons.folder_outlined,
                            ),
                            title: Text(
                              entry.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => ref
                                .read(
                                  hostDirectoryBrowserControllerProvider(
                                    hostId,
                                  ).notifier,
                                )
                                .open(entry.path),
                          );
                        },
                      ),
              ),
              if (data.listing != null)
                Padding(
                  padding: AleraTokens.pagePadding,
                  child: FilledButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pop(data.listing!.path),
                    icon: const Icon(Icons.check),
                    label: Text(actionLabel),
                  ),
                ),
            ],
          ),
          AsyncError(:final error) => Center(
            child: Padding(
              padding: AleraTokens.contentPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(error.toString(), textAlign: TextAlign.center),
                  const SizedBox(height: AleraTokens.spaceLg),
                  FilledButton(
                    onPressed: () => ref.invalidate(
                      hostDirectoryBrowserControllerProvider(hostId),
                    ),
                    child: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _PathHeader extends StatelessWidget {
  const _PathHeader({required this.path, required this.onUp});

  final String? path;
  final VoidCallback? onUp;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Row(
          children: <Widget>[
            IconButton(
              onPressed: onUp,
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Parent Folder',
            ),
            const SizedBox(width: AleraTokens.spaceSm),
            Expanded(
              child: Text(
                path ?? 'Host Locations',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: AleraTokens.monoFontFamily,
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
