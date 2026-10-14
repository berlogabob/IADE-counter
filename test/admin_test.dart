import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iade_counter/admin.dart';

Future<void> timing(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: AdminPage()));
  await tester.enterText(find.byType(TextField), 'Team A\nTeam B');
  await tester.pump();
  await tester.tap(find.text('Next'));
  await tester.pump();
}

void main() {
  testWidgets('presenters are required before Next', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AdminPage()));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), 'Team A\nTeam B');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('timing shows all five defaults', (tester) async {
    await timing(tester);
    expect(find.text('2 of 4 · Timing'), findsOneWidget);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .map((f) => f.controller!.text),
      ['2', '15', '1', '10', '1'],
    );
  });
  testWidgets('warning must be shorter than presentation', (tester) async {
    await timing(tester);
    await tester.enterText(find.byType(TextField).at(2), '20');
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('2 of 4 · Timing'), findsOneWidget);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).style!.color,
      Colors.red[700],
    );
  });
}
