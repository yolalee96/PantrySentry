import 'package:flutter_test/flutter_test.dart';

import 'package:pantrybuddy/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(PantryBuddyApp());
    await tester.pump();
    expect(find.byType(PantryBuddyApp), findsOneWidget);
  });
}