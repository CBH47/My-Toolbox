import 'package:flutter_test/flutter_test.dart';

import 'package:my_toolbox/main.dart';
import 'package:my_toolbox/home_page.dart';

void main() {
  testWidgets('App loads HomePage', (WidgetTester tester) async {
    await tester.pumpWidget(const ToolboxApp());

    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('Toolbox Inventory'), findsOneWidget);
    expect(find.text('Total Items'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
  });
}
