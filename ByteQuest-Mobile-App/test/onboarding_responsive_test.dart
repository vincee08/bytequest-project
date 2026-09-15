import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/screens/onboarding/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('onboarding content wraps without overflow on phone viewports',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final size in <Size>[
      const Size(320, 568),
      const Size(412, 915),
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const OnboardingScreen(),
          routes: {
            '/get-started': (_) => const SizedBox.shrink(),
          },
        ),
      );
      await tester.pump();

      expect(
        tester.takeException(),
        isNull,
        reason: 'Onboarding must not overflow at $size.',
      );
      expect(
        find.text('Build CSS NC II skills through play'),
        findsOneWidget,
      );
      expect(find.text('Next'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
