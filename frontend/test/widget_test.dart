import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:strollwise/app/app.dart';

void main() {
  testWidgets('app boots to explore tab', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: StrollWiseApp()));
    await tester.pumpAndSettle();
    expect(find.text('Explore'), findsOneWidget);
  });
}
