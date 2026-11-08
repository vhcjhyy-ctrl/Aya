import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aya_app/widgets/memorial_dua_dialog.dart';

void main() {
  testWidgets('shows the supplication for all three named family members',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (dialogContext) => MemorialDuaDialog(
                      onContinue: () => Navigator.of(dialogContext).pop(),
                    ),
                  );
                },
                child: const Text('Open prayer'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open prayer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('سعدية محمد قشطة'), findsOneWidget);
    expect(find.textContaining('عيد الزبلاوي'), findsOneWidget);
    expect(find.textContaining('أحمد السيد السيسي'), findsOneWidget);
    expect(find.text('آمين، متابعة'), findsOneWidget);

    await tester.tap(find.text('آمين، متابعة'));
    await tester.pumpAndSettle();

    expect(find.byType(MemorialDuaDialog), findsNothing);
  });
}
