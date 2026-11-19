import 'package:bytequest/core/theme/app_theme.dart';
import 'package:bytequest/core/widgets/app_button.dart';
import 'package:bytequest/data/account_content_data.dart';
import 'package:bytequest/screens/splash/splash_screen.dart';
import 'package:bytequest/services/app_version_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(AppVersionChecker checker, {double textScale = 1}) => MaterialApp(
      theme: AppTheme.lightTheme,
      routes: {
        '/onboarding': (_) => const Scaffold(body: Text('onboarding route')),
        '/dashboard': (_) => const Scaffold(body: Text('dashboard route')),
      },
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SplashScreen(checkAppVersion: checker, splashDelay: Duration.zero),
    );

AppVersionCheck _result(AppVersionStatus status, {String? minimum}) =>
    AppVersionCheck(
        status: status, currentVersion: kAppVersion, minimumVersion: minimum);

void main() {
  test('the app reports version 1.2.0', () {
    expect(kAppVersion, '1.2.0');
  });

  test('versions compare numerically and ignore build metadata', () {
    expect(parseAppVersion('1.2.0+3'), [1, 2, 0]);
    expect(parseAppVersion(' 1.10 '), [1, 10]);
    expect(parseAppVersion('1.2.0-beta.1'), [1, 2, 0]);
    expect(parseAppVersion('one.two'), isNull);
    expect(parseAppVersion(''), isNull);
    expect(compareAppVersions([1, 2], [1, 2, 0]), 0);
    expect(compareAppVersions([1, 9, 9], [1, 10, 0]), isNegative);
    expect(compareAppVersions([2, 0, 0], [1, 99, 99]), isPositive);
  });

  test('only a valid newer minimum blocks the app (fail open otherwise)', () {
    expect(evaluateAppVersion(current: '1.2.0', minimum: '1.2.0').status,
        AppVersionStatus.supported);
    expect(evaluateAppVersion(current: '1.2.0', minimum: '1.1.9').status,
        AppVersionStatus.supported);
    expect(evaluateAppVersion(current: '1.2.0', minimum: '1.3.0').status,
        AppVersionStatus.updateRequired);
    expect(evaluateAppVersion(current: '1.1.0', minimum: '1.2.0').status,
        AppVersionStatus.updateRequired);
    expect(evaluateAppVersion(current: '1.2.0', minimum: null).status,
        AppVersionStatus.supported);
    expect(evaluateAppVersion(current: '1.2.0', minimum: 'latest').status,
        AppVersionStatus.supported);
  });

  testWidgets('a version below the minimum shows a blocking update screen',
      (tester) async {
    var checks = 0;
    var status = AppVersionStatus.updateRequired;
    await tester.pumpWidget(_app(() async {
      checks++;
      return _result(status, minimum: '1.3.0');
    }));
    await tester.pumpAndSettle();

    expect(find.text(AccountContentData.updateRequiredTitle), findsOneWidget);
    expect(find.text(AccountContentData.updateRequiredBody(kAppVersion, '1.3.0')),
        findsOneWidget);
    expect(find.text('onboarding route'), findsNothing);
    expect(find.bySemanticsLabel(AccountContentData.updateCheckAgainSemantics),
        findsOneWidget);

    // The system back gesture cannot skip the update screen.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text(AccountContentData.updateRequiredTitle), findsOneWidget);

    // Still outdated: checking again keeps the learner on the update screen.
    await tester.ensureVisible(find.text(AccountContentData.updateCheckAgain));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AccountContentData.updateCheckAgain));
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(find.text(AccountContentData.updateRequiredTitle), findsOneWidget);

    // Once the minimum is met the normal start-up flow continues.
    status = AppVersionStatus.supported;
    await tester.ensureVisible(find.text(AccountContentData.updateCheckAgain));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AccountContentData.updateCheckAgain));
    await tester.pumpAndSettle();
    expect(find.text('onboarding route'), findsOneWidget);
  });

  testWidgets('an offline check fails open with retry and continue',
      (tester) async {
    var checks = 0;
    await tester.pumpWidget(_app(() async {
      checks++;
      return _result(AppVersionStatus.unknown);
    }));
    await tester.pumpAndSettle();

    expect(find.text(AccountContentData.versionCheckFailedTitle), findsOneWidget);
    expect(find.text(AccountContentData.updateRequiredTitle), findsNothing);
    await tester.ensureVisible(find.text(AccountContentData.versionCheckRetry));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AccountContentData.versionCheckRetry));
    await tester.pumpAndSettle();
    expect(checks, 2);
    expect(find.text(AccountContentData.versionCheckFailedTitle), findsOneWidget);

    await tester.ensureVisible(find.text(AccountContentData.versionCheckContinue));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AccountContentData.versionCheckContinue));
    await tester.pumpAndSettle();
    expect(find.text('onboarding route'), findsOneWidget);
  });

  testWidgets('a supported version continues straight to the start flow',
      (tester) async {
    await tester.pumpWidget(_app(() async => _result(AppVersionStatus.supported,
        minimum: '1.2.0')));
    await tester.pumpAndSettle();
    expect(find.text(AccountContentData.updateRequiredTitle), findsNothing);
    expect(find.text(AccountContentData.versionCheckFailedTitle), findsNothing);
    expect(find.text('onboarding route'), findsOneWidget);
  });

  testWidgets('the update screen fits a small phone with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(
        () async => _result(AppVersionStatus.updateRequired, minimum: '9.0.0'),
        textScale: 2));
    await tester.pumpAndSettle();
    expect(find.text(AccountContentData.updateRequiredTitle), findsOneWidget);
    expect(tester.takeException(), isNull);
    final button = tester.getSize(
        find.widgetWithText(AppButton, AccountContentData.updateCheckAgain));
    expect(button.height, greaterThanOrEqualTo(48));
  });
}
