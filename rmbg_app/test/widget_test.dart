import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rmbg_app/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RMBGApp());

    expect(find.text('Background Remover'), findsOneWidget);
    expect(find.text('Pick Image'), findsOneWidget);
  });
}