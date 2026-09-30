import 'package:flutter_test/flutter_test.dart';

import 'package:civicpulse/main.dart';

void main() {
  testWidgets('shows the citizen reporting experience', (tester) async {
    await tester.pumpWidget(const CivicPulseApp());

    expect(find.text('Report a community issue'), findsOneWidget);
    expect(find.text('BRICS innovation · Citizen voice to public good'),
        findsOneWidget);
    expect(find.text('Submit report'), findsOneWidget);
    expect(find.text('Country'), findsOneWidget);
    expect(find.text('Region'), findsOneWidget);
    expect(find.text('Guntur'), findsOneWidget);
  });
}
