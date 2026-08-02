import 'package:android_ssh_codex/src/protocol/codex_remote_api.dart';
import 'package:android_ssh_codex/src/ui/turn_settings_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const models = [
    RemoteModel(
      id: 'sol-entry',
      model: 'gpt-5.6-sol',
      displayName: 'GPT-5.6 Sol',
      description: 'Frontier coding model',
      isDefault: true,
      defaultReasoningEffort: 'high',
      supportedReasoningEfforts: [
        RemoteReasoningEffort(
          effort: 'medium',
          description: 'Fast and capable',
        ),
        RemoteReasoningEffort(
          effort: 'high',
          description: 'Deeper reasoning',
        ),
      ],
    ),
    RemoteModel(
      id: 'terra-entry',
      model: 'gpt-5.6-terra',
      displayName: 'GPT-5.6 Terra',
      description: 'Balanced coding model',
      isDefault: false,
      defaultReasoningEffort: 'medium',
      supportedReasoningEfforts: [
        RemoteReasoningEffort(
          effort: 'medium',
          description: 'Balanced reasoning',
        ),
      ],
    ),
  ];

  testWidgets('selecting a model selects its advertised default effort',
      (tester) async {
    var selection = const TurnSettings();
    late StateSetter updateHost;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return TurnSettingsPicker(
              models: models,
              value: selection,
              onChanged: (value) => updateHost(() => selection = value),
            );
          },
        ),
      ),
    ));

    expect(find.text('Server default'), findsOneWidget);
    await tester.tap(find.byKey(const Key('turn-model-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GPT-5.6 Sol').last);
    await tester.pumpAndSettle();

    expect(selection.model, 'gpt-5.6-sol');
    expect(selection.effort, 'high');
    expect(find.text('high'), findsOneWidget);
  });

  testWidgets('effort menu contains only values advertised by the model',
      (tester) async {
    var selection = const TurnSettings(
      model: 'gpt-5.6-sol',
      effort: 'high',
    );
    late StateSetter updateHost;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            updateHost = setState;
            return TurnSettingsPicker(
              models: models,
              value: selection,
              onChanged: (value) => updateHost(() => selection = value),
            );
          },
        ),
      ),
    ));

    await tester.tap(find.byKey(const Key('turn-effort-selector')));
    await tester.pumpAndSettle();

    expect(find.text('medium'), findsOneWidget);
    expect(find.text('high'), findsWidgets);
    expect(find.text('xhigh'), findsNothing);
    await tester.tap(find.text('medium'));
    await tester.pumpAndSettle();

    expect(selection.effort, 'medium');
  });
}
