import 'package:permission_handler/permission_handler.dart';

/// The permissions the app asks for.
enum AppPermission { camera, microphone }

/// The outcome of asking for a permission.
class PermissionResult {
  const PermissionResult({
    required this.permission,
    required this.granted,
    required this.permanentlyDenied,
  });

  /// The permission that was asked for.
  final AppPermission permission;

  /// Whether the permission was granted.
  final bool granted;

  /// Whether the permission was denied for good, so the system will not ask
  /// again and the user has to go to the settings of the system.
  final bool permanentlyDenied;

  @override
  String toString() =>
      'PermissionResult(${permission.name}, granted: $granted, '
      'permanentlyDenied: $permanentlyDenied)';
}

/// Asks the operating system for the permissions.
///
/// The interface exists so the onboarding can be tested without the real
/// plugin, which only works on a device.
abstract class PermissionGateway {
  /// Whether the permission has already been granted.
  Future<bool> isGranted(AppPermission permission);

  /// Asks the user for the permission.
  Future<PermissionResult> request(AppPermission permission);

  /// Opens the settings page of the app in the system.
  Future<bool> openSettings();
}

/// The real gateway, backed by `permission_handler`.
class PermissionHandlerGateway implements PermissionGateway {
  const PermissionHandlerGateway();

  @override
  Future<bool> isGranted(AppPermission permission) async {
    final status = await _status(permission);
    return status?.isGranted ?? false;
  }

  @override
  Future<PermissionResult> request(AppPermission permission) async {
    try {
      final status = await _permission(permission)!.request();
      return PermissionResult(
        permission: permission,
        granted: status.isGranted,
        permanentlyDenied: status.isPermanentlyDenied,
      );
    } catch (_) {
      // The plugin is not available (for example in a unit test).
      return PermissionResult(
        permission: permission,
        granted: false,
        permanentlyDenied: false,
      );
    }
  }

  @override
  Future<bool> openSettings() => openAppSettings();

  Permission? _permission(AppPermission permission) {
    switch (permission) {
      case AppPermission.camera:
        return Permission.camera;
      case AppPermission.microphone:
        return Permission.microphone;
    }
  }

  Future<PermissionStatus?> _status(AppPermission permission) async {
    try {
      return await _permission(permission)?.status;
    } catch (_) {
      // The plugin is not available (for example in a unit test).
      return null;
    }
  }
}
