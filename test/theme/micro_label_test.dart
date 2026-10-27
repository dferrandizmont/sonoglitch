import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/theme/app_theme.dart';
import 'package:sonoglitch/theme/micro_label.dart';

void main() {
  testWidgets('uses uppercase micro typography with a single-line ellipsis', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MicroLabel('Motion'))),
    );
    final text = tester.widget<Text>(find.text('MOTION'));
    expect(text.style, AppTheme.micro);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('supports role colour and size at large text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SizedBox(
              width: 70,
              child: MicroLabel(
                'A long style name',
                color: AppTheme.signalCyan,
                fontSize: AppTheme.styleNameFontSize,
              ),
            ),
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('A LONG STYLE NAME'));
    expect(text.style!.fontSize, 13);
    expect(text.style!.color, AppTheme.signalCyan);
    expect(text.style!.letterSpacing, 1.2);
    expect(tester.takeException(), isNull);
  });
}
