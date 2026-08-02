import 'package:flutter/material.dart';

import '../protocol/codex_remote_api.dart';

final class TurnSettings {
  const TurnSettings({this.model, this.effort});

  final String? model;
  final String? effort;
}

class TurnSettingsPicker extends StatelessWidget {
  const TurnSettingsPicker({
    required this.models,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  static const _serverDefault = '';

  final List<RemoteModel> models;
  final TurnSettings value;
  final ValueChanged<TurnSettings> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selectedModel = models
        .where((candidate) => candidate.model == value.model)
        .firstOrNull;
    final efforts = selectedModel == null
        ? const <RemoteReasoningEffort>[]
        : _effortsFor(selectedModel);
    final selectedEffort = efforts.any((item) => item.effort == value.effort)
        ? value.effort
        : selectedModel?.defaultReasoningEffort;

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: SizedBox(
            key: const Key('turn-model-selector'),
            child: DropdownButtonFormField<String>(
              key: Key('turn-model-value-${value.model}'),
              initialValue: value.model ?? _serverDefault,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Model',
                isDense: true,
                prefixIcon: Icon(Icons.memory_outlined),
              ),
              items: [
                const DropdownMenuItem(
                  value: _serverDefault,
                  child: Text('Server default'),
                ),
                for (final model in models)
                  DropdownMenuItem(
                    value: model.model,
                    child: Text(
                      model.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: enabled
                  ? (modelName) {
                      if (modelName == null || modelName == _serverDefault) {
                        onChanged(const TurnSettings());
                        return;
                      }
                      final model = models
                          .where((candidate) => candidate.model == modelName)
                          .firstOrNull;
                      if (model == null) return;
                      onChanged(TurnSettings(
                        model: model.model,
                        effort: model.defaultReasoningEffort,
                      ));
                    }
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: SizedBox(
            key: const Key('turn-effort-selector'),
            child: DropdownButtonFormField<String>(
              key: Key(
                'turn-effort-value-${value.model}-$selectedEffort',
              ),
              initialValue: selectedEffort,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Effort',
                isDense: true,
                prefixIcon: Icon(Icons.psychology_outlined),
              ),
              hint: const Text('Default'),
              items: [
                for (final option in efforts)
                  DropdownMenuItem(
                    value: option.effort,
                    child: option.description.isEmpty
                        ? Text(option.effort)
                        : Tooltip(
                            message: option.description,
                            child: Text(option.effort),
                          ),
                  ),
              ],
              onChanged: enabled && selectedModel != null
                  ? (effort) {
                      if (effort == null) return;
                      onChanged(TurnSettings(
                        model: selectedModel.model,
                        effort: effort,
                      ));
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  List<RemoteReasoningEffort> _effortsFor(RemoteModel model) {
    if (model.supportedReasoningEfforts
        .any((item) => item.effort == model.defaultReasoningEffort)) {
      return model.supportedReasoningEfforts;
    }
    return [
      RemoteReasoningEffort(
        effort: model.defaultReasoningEffort,
        description: '',
      ),
      ...model.supportedReasoningEfforts,
    ];
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
