import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../profiles/host_profile.dart';
import 'profile_editor.dart';

class HostsView extends StatelessWidget {
  const HostsView({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'SSH hosts',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _edit(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add host'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: controller.profiles.isEmpty
                        ? const _EmptyHosts()
                        : ListView.separated(
                            itemCount: controller.profiles.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) => _HostRow(
                              profile: controller.profiles[index],
                              selected: controller.selectedHostId ==
                                  controller.profiles[index].id,
                              busy: controller.connectionPhase ==
                                  RemoteConnectionPhase.connecting,
                              onConnect: () => controller
                                  .connectHost(controller.profiles[index]),
                              onEdit: () => _edit(
                                context,
                                controller.profiles[index],
                              ),
                              onDelete: () => _delete(
                                context,
                                controller.profiles[index],
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Future<void> _edit(BuildContext context, [HostProfile? profile]) async {
    final secret =
        profile == null ? const HostSecret() : await controller.readSecret(profile.id);
    if (!context.mounted) return;
    final draft = await showDialog<ProfileDraft>(
      context: context,
      builder: (_) => ProfileEditor(profile: profile, secret: secret),
    );
    if (draft != null) {
      await controller.saveProfile(draft.profile, draft.secret);
    }
  }

  Future<void> _delete(BuildContext context, HostProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove host?'),
        content: Text('Remove ${profile.label} and its stored credentials?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteProfile(profile.id);
  }
}

class _EmptyHosts extends StatelessWidget {
  const _EmptyHosts();

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lan_outlined,
                size: 46,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Connect your first SSH host',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
}

class _HostRow extends StatelessWidget {
  const _HostRow({
    required this.profile,
    required this.selected,
    required this.busy,
    required this.onConnect,
    required this.onEdit,
    required this.onDelete,
  });

  final HostProfile profile;
  final bool selected;
  final bool busy;
  final VoidCallback onConnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.45)
            : null,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            child: Text(profile.label.characters.first.toUpperCase()),
          ),
          title: Text(profile.label),
          subtitle: Text(
            '${profile.user}@${profile.hostName}:${profile.port}'
            '${profile.proxyJump == null ? '' : ' via ${profile.proxyJump!.hostName}'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Wrap(
            spacing: 2,
            children: [
              IconButton(
                tooltip: 'Edit host',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: 'Host actions',
                onSelected: (value) {
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('Remove')),
                ],
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: busy ? null : onConnect,
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Connect'),
              ),
            ],
          ),
        ),
      );
}
