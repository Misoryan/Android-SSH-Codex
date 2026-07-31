import 'package:flutter/material.dart';

import '../../app_controller.dart';

class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({required this.phase, super.key});

  final RemoteConnectionPhase phase;

  @override
  Widget build(BuildContext context) {
    final connected = phase == RemoteConnectionPhase.connected;
    final busy = phase == RemoteConnectionPhase.connecting ||
        phase == RemoteConnectionPhase.reconnecting;
    final color = connected
        ? Theme.of(context).colorScheme.primary
        : busy
            ? Theme.of(context).colorScheme.tertiary
            : Theme.of(context).colorScheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          connected
              ? 'Connected'
              : busy
                  ? 'Connecting'
                  : 'Offline',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}
