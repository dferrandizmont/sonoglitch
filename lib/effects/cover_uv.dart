import 'dart:ui';

/// Maps destination UV coordinates to a centered, cover-fitted image crop.
///
/// Apply the result as `uv * scale + offset`. Invalid sizes use the identity
/// mapping; callers should skip painting destinations with invalid dimensions.
({Offset scale, Offset offset}) coverUv(Size imageSize, Size destinationSize) {
  if (!_validSize(imageSize) || !_validSize(destinationSize)) {
    return (scale: const Offset(1, 1), offset: Offset.zero);
  }

  final imageAspect = imageSize.width / imageSize.height;
  final destinationAspect = destinationSize.width / destinationSize.height;
  final scale = imageAspect > destinationAspect
      ? Offset(destinationAspect / imageAspect, 1)
      : Offset(1, imageAspect / destinationAspect);
  return (scale: scale, offset: Offset((1 - scale.dx) / 2, (1 - scale.dy) / 2));
}

bool _validSize(Size size) =>
    size.width.isFinite &&
    size.height.isFinite &&
    size.width > 0 &&
    size.height > 0;
