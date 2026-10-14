import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iade_counter/quick.dart';
import 'package:iade_counter/welcome.dart';

void main() {
  testWidgets('welcome offers quick timer and new session', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomePage()));
    expect(find.text('Quick timer'), findsOneWidget);
    expect(find.text('New session'), findsOneWidget);
    await tester.tap(find.text('Quick timer'));
    await tester.pumpAndSettle();
    expect(find.byType(QuickPage), findsOneWidget);
  });

  testWidgets('quick timer starts with defaults and controls the loop', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: QuickPage()));
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Setup'), findsOneWidget);
    expect(find.text('02:00'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Resume'), findsOneWidget);
    for (final label in ['Presentation', 'Q&A', 'Pack', 'Setup']) {
      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(5));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('invalid times stay in settings; comma decimals work', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: QuickPage()));
    final fields = find.byType(TextField);
    for (final value in ['-1', '15', '0', 'NaN']) {
      await tester.enterText(fields.at(2), value);
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(5));
      expect(find.byType(SnackBar), findsOneWidget);
    }
    await tester.enterText(fields.at(2), '0,5');
    await tester.enterText(fields.at(0), '0');
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(find.text('Presentation'), findsOneWidget);
    expect(find.text('15:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
