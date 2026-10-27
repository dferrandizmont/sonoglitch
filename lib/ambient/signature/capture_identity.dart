import '../../features/result/capture_result.dart';
import 'signature_state.dart';

export 'signature_state.dart' show CaptureIdentity;

/// Import this library to read the identity already carried by ambient.
/// Legacy/test inputs have no identity; recomposition never creates another.
extension CaptureResultIdentity on CaptureResult {
  CaptureIdentity? get identity => ambient.identity;
  CaptureSignature? get captureSignature => ambient.captureSignature;
}

/// The printed form of the photo ID: two groups of four, as `A3F9-17C2`.
extension CaptureIdentityDisplay on CaptureIdentity {
  String get displayId => photoId.length == 8
      ? '${photoId.substring(0, 4)}-${photoId.substring(4)}'
      : photoId;
}
