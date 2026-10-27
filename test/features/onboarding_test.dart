import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/features/onboarding/onboarding_screen.dart';
import 'package:sonoglitch/features/onboarding/permission_gateway.dart';
import 'package:sonoglitch/l10n/app_localizations.dart';
import 'package:sonoglitch/theme/app_theme.dart';

/// A permission gateway the test drives by hand.
class FakePermissionGateway implements PermissionGateway {
  FakePermissionGateway({
    this.cameraGranted = false,
    this.microphoneGranted = false,
    this.cameraPermanentlyDenied = false,
  });

  bool cameraGranted;
  bool microphoneGranted;
  bool cameraPermanentlyDenied;

  final List<AppPermission> requested = [];
  int settingsOpened = 0;

  @override
  Future<bool> isGranted(AppPermission permission) async =>
      switch (permission) {
        AppPermission.camera => cameraGranted,
        AppPermission.microphone => microphoneGranted,
      };

  @override
  Future<PermissionResult> request(AppPermission permission) async {
    requested.add(permission);
    final granted = switch (permission) {
      AppPermission.camera => cameraGranted,
      AppPermission.microphone => microphoneGranted,
    };
    return PermissionResult(
      permission: permission,
      granted: granted,
      permanentlyDenied:
          permission == AppPermission.camera && cameraPermanentlyDenied,
    );
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }
}

Future<void> pumpOnboarding(
  WidgetTester tester,
  FakePermissionGateway gateway, {
  required void Function(bool microphoneGranted) onContinue,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OnboardingScreen(permissions: gateway, onContinue: onContinue),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final gatewayKind in [
    'request',
    'microphone refused',
    'camera refused permanently',
  ]) {
    testWidgets(
      'small onboarding remains scrollable and themed: $gatewayKind',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = FakePermissionGateway(
          cameraGranted: gatewayKind == 'microphone refused',
          cameraPermanentlyDenied: gatewayKind == 'camera refused permanently',
        );
        await pumpOnboarding(
          tester,
          gateway,
          onContinue: (_) {},
          textScale: 1.3,
        );
        final button = find.byType(FilledButton);
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        if (gatewayKind == 'camera refused permanently') {
          await tester.tap(button);
          await tester.pumpAndSettle();
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          expect(find.text('Open system settings'), findsOneWidget);
        }
        expect(button.hitTestable(), findsOneWidget);
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        expect(
          tester.widget<FilledButton>(button).style,
          isNull,
          reason: 'the global button theme owns its appearance',
        );
        final context = tester.element(button);
        expect(
          FilledButtonTheme.of(context).style!.animationDuration,
          Duration.zero,
        );
        final shape =
            Theme.of(context).filledButtonTheme.style!.shape!.resolve({})!
                as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(AppTheme.radiusSm));
        final headline = tester.widget<Text>(
          find.textContaining('A camera that lets'),
        );
        // Material merges the headline token with its typography defaults.
        expect(headline.style, Theme.of(context).textTheme.headlineMedium);
        final style = headline.style!;
        expect(style.color, AppTheme.headline.color);
        expect(style.fontFamily, AppTheme.headline.fontFamily);
        expect(style.fontSize, AppTheme.headline.fontSize);
        expect(style.fontWeight, AppTheme.headline.fontWeight);
        expect(style.letterSpacing, AppTheme.headline.letterSpacing);
        expect(style.height, AppTheme.headline.height);
        final privacy = find
            .ancestor(
              of: find.textContaining('never recorded'),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container && widget.decoration is BoxDecoration,
              ),
            )
            .first;
        expect(
          (tester.widget<Container>(privacy).decoration! as BoxDecoration)
              .borderRadius,
          BorderRadius.circular(AppTheme.radiusMd),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('explains the idea and that no audio is recorded', (
    tester,
  ) async {
    final gateway = FakePermissionGateway();
    await pumpOnboarding(tester, gateway, onContinue: (_) {});

    expect(find.textContaining('A camera that lets'), findsOneWidget);
    expect(find.textContaining('never recorded'), findsOneWidget);
  });

  testWidgets('is skipped when the permissions are already granted', (
    tester,
  ) async {
    final gateway = FakePermissionGateway(
      cameraGranted: true,
      microphoneGranted: true,
    );
    var continued = false;
    await pumpOnboarding(tester, gateway, onContinue: (_) => continued = true);

    expect(continued, isTrue);
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('asks for the camera and the microphone', (tester) async {
    final gateway = FakePermissionGateway();
    var continued = false;
    await pumpOnboarding(tester, gateway, onContinue: (_) => continued = true);

    await tester.tap(find.text('Allow camera and microphone'));
    await tester.pumpAndSettle();

    expect(gateway.requested, contains(AppPermission.camera));
    expect(gateway.requested, contains(AppPermission.microphone));
    expect(continued, isFalse);
  });

  testWidgets('continues when the microphone is refused', (tester) async {
    final gateway = FakePermissionGateway(cameraGranted: true);
    var continued = false;
    await pumpOnboarding(tester, gateway, onContinue: (_) => continued = true);

    expect(find.textContaining('No microphone'), findsOneWidget);

    await tester.tap(find.text('Continue without microphone'));
    await tester.pumpAndSettle();

    expect(continued, isTrue);
  });

  testWidgets('offers the settings when the camera is refused for good', (
    tester,
  ) async {
    final gateway = FakePermissionGateway(cameraPermanentlyDenied: true);
    await pumpOnboarding(tester, gateway, onContinue: (_) {});

    // The first try asks the system, and the system refuses for good.
    await tester.tap(find.text('Allow camera and microphone'));
    await tester.pumpAndSettle();

    expect(find.text('Open system settings'), findsOneWidget);

    await tester.tap(find.text('Open system settings'));
    await tester.pumpAndSettle();

    expect(gateway.settingsOpened, 1);
  });
}
