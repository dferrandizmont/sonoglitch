import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/app_theme.dart';
import 'permission_gateway.dart';

/// The first screen of the app.
///
/// It explains the idea in one sentence, says that the audio is never
/// recorded, and asks for the camera and the microphone. When both
/// permissions are already granted the screen is skipped.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.permissions,
    required this.onContinue,
  });

  /// How the permissions are asked for.
  final PermissionGateway permissions;

  /// Called when the app can continue to the viewfinder.
  ///
  /// It says whether the microphone was granted: without it the noise stays
  /// at zero.
  final void Function(bool microphoneGranted) onContinue;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _checking = true;
  bool _busy = false;
  bool _cameraGranted = false;
  bool _microphoneGranted = false;
  bool _cameraPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final camera = await widget.permissions.isGranted(AppPermission.camera);
    final microphone = await widget.permissions.isGranted(
      AppPermission.microphone,
    );
    if (!mounted) return;
    if (camera && microphone) {
      // The screen is not needed at all.
      setState(() => _checking = false);
      widget.onContinue(true);
      return;
    }
    setState(() {
      _cameraGranted = camera;
      _microphoneGranted = microphone;
      _checking = false;
    });
  }

  Future<void> _request() async {
    if (_busy) return;
    setState(() => _busy = true);

    final camera = await widget.permissions.request(AppPermission.camera);
    final microphone = await widget.permissions.request(
      AppPermission.microphone,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _cameraGranted = camera.granted;
      _microphoneGranted = microphone.granted;
      _cameraPermanentlyDenied = camera.permanentlyDenied;
    });

    if (camera.granted && microphone.granted) {
      widget.onContinue(microphone.granted);
    }
  }

  Future<void> _openSettings() async {
    await widget.permissions.openSettings();
    if (!mounted) return;
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceLg),
          child: _checking
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Spacer(),
                            Text(
                              l10n.onboardingHeadline,
                              style: theme.textTheme.headlineMedium,
                            ),
                            const SizedBox(height: AppTheme.spaceMd),
                            Text(
                              l10n.onboardingIdea,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: AppTheme.textSecondary,
                                height: AppTheme.body.height,
                              ),
                            ),
                            const SizedBox(height: AppTheme.spaceLg),
                            Container(
                              padding: const EdgeInsets.all(AppTheme.spaceMd),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                border: Border.all(color: AppTheme.outline),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.mic_off_outlined,
                                    color: AppTheme.accent,
                                    size: AppTheme.overlayIconSize,
                                  ),
                                  const SizedBox(width: AppTheme.spaceSm),
                                  Expanded(
                                    child: Text(
                                      l10n.onboardingPrivacy,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            color: AppTheme.textPrimary,
                                            height: AppTheme.body.height,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (_cameraPermanentlyDenied) ...[
                              Text(
                                l10n.onboardingPermanentlyDenied,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.danger,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spaceSm),
                              _PrimaryButton(
                                label: l10n.onboardingOpenSettings,
                                icon: Icons.settings_outlined,
                                onPressed: _openSettings,
                              ),
                            ] else if (!_cameraGranted) ...[
                              Text(
                                l10n.onboardingCameraDenied,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.danger,
                                ),
                              ),
                              const SizedBox(height: AppTheme.spaceSm),
                              _PrimaryButton(
                                label: l10n.onboardingGrant,
                                icon: Icons.photo_camera_outlined,
                                busy: _busy,
                                onPressed: _request,
                              ),
                            ] else ...[
                              if (!_microphoneGranted) ...[
                                Text(
                                  l10n.onboardingMicrophoneDeniedNotice,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                    height: AppTheme.bodySmall.height,
                                  ),
                                ),
                                const SizedBox(height: AppTheme.spaceSm),
                              ],
                              _PrimaryButton(
                                label: _microphoneGranted
                                    ? l10n.onboardingGrant
                                    : l10n.onboardingSkip,
                                icon: _microphoneGranted
                                    ? Icons.mic_none_outlined
                                    : Icons.arrow_forward,
                                busy: _busy,
                                onPressed: _microphoneGranted
                                    ? _request
                                    : () => widget.onContinue(false),
                              ),
                            ],
                            const SizedBox(height: AppTheme.spaceSm),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: AppTheme.spaceMd,
                height: AppTheme.spaceMd,
                child: CircularProgressIndicator(
                  strokeWidth: AppTheme.ringStrokeWidth,
                ),
              )
            : Icon(icon),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
    if (!MediaQuery.disableAnimationsOf(context)) return button;
    // Preserve the global appearance while skipping the state transition.
    return FilledButtonTheme(
      data: FilledButtonThemeData(
        style: FilledButtonTheme.of(context).style
            ?.copyWith(animationDuration: Duration.zero),
      ),
      child: button,
    );
  }
}
