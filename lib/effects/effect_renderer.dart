import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../ambient/ambient_state.dart';
import 'cover_uv.dart';
import 'style_definition.dart';

/// Applies a [StyleDefinition] shader to an image.
///
/// PUBLIC CONTRACT (the effects module may change the implementation, not the API):
/// - [load] compiles the style's shader once; keep the renderer and reuse it.
/// - [paint] draws [image] cover-fitted to [size] on [canvas] with the effect.
/// - [renderToImage] produces a still of [source] at its own resolution,
///   scaled down so its longest side is at most [maxSide].
/// The caller owns this renderer and must call [dispose] when it is no longer
/// used by either a live view or a still render.
class EffectRenderer {
  EffectRenderer._(this.style, this._shader);

  final StyleDefinition style;
  final ui.FragmentShader _shader;
  bool _disposed = false;

  static Future<EffectRenderer> load(StyleDefinition style) async {
    final program = await ui.FragmentProgram.fromAsset(style.shaderAsset);
    return EffectRenderer._(style, program.fragmentShader());
  }

  void paint(
    Canvas canvas,
    Size size, {
    required ui.Image image,
    required AmbientState ambient,
    required double time,
  }) {
    _checkNotDisposed();
    // Shader floats must remain finite, and the displacement budget of the
    // signature helpers is defined against at least one pixel of short side.
    // Such extreme sizes cannot represent a useful canvas.
    if (!size.width.isFinite ||
        !size.height.isFinite ||
        size.width < 1 ||
        size.height < 1 ||
        size.width > 1000000000 ||
        size.height > 1000000000) {
      return;
    }

    final uniforms = uniformValues(
      size: size,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
      ambient: ambient,
      time: time,
    );
    for (var index = 0; index < uniforms.length; index++) {
      _shader.setFloat(index, uniforms[index]);
    }
    // Samplers have a separate index space. Write every float on every paint.
    _shader.setImageSampler(0, image, filterQuality: FilterQuality.low);
    canvas.drawRect(Offset.zero & size, Paint()..shader = _shader);
  }

  /// The twenty-eight-float ABI shared by preview and still rendering.
  /// Kept independently testable; indices 0..19 retain their original meaning.
  @visibleForTesting
  static List<double> uniformValues({
    required Size size,
    required Size imageSize,
    required AmbientState ambient,
    required double time,
  }) {
    final crop = coverUv(imageSize, size);
    final direction = _trailDirection(ambient.motionDirX, ambient.motionDirY);
    final axis = _axis(ambient.signature.axisX, ambient.signature.axisY);
    return [
      size.width, // 0
      size.height, // 1
      _control(ambient.noise, 0), // 2
      _control(ambient.light, 0.5), // 3
      _control(ambient.motion, 0), // 4
      time.isFinite ? time.clamp(0.0, 1000000.0) : 0, // 5
      direction.dx, // 6
      direction.dy, // 7
      crop.scale.dx, // 8
      crop.scale.dy, // 9
      crop.offset.dx, // 10
      crop.offset.dy, // 11
      _control(ambient.bass, 0), // 12
      _control(ambient.mid, 0), // 13
      _control(ambient.treble, 0), // 14
      _control(ambient.seed, 0), // 15
      _control(ambient.signature.x, 0), // 16
      _control(ambient.signature.y, 0), // 17
      _control(ambient.signature.z, 0), // 18
      _control(ambient.signature.w, 0), // 19
      _signed(ambient.signature.warmth), // 20
      _signed(ambient.signature.hue), // 21
      _chroma(ambient.signature.chromaAllowance), // 22
      _signed(ambient.signature.tilt), // 23
      axis.dx, // 24
      axis.dy, // 25
      _signed(ambient.signature.pulse), // 26
      _signed(ambient.signature.reserved), // 27
    ];
  }

  Future<ui.Image> renderToImage(
    ui.Image source, {
    required AmbientState ambient,
    required double time,
    int maxSide = 2048,
  }) async {
    _checkNotDisposed();
    if (maxSide <= 0) {
      throw ArgumentError.value(maxSide, 'maxSide', 'Must be positive.');
    }
    final scale = math.min(
      1.0,
      maxSide / math.max(source.width, source.height),
    );
    final width = math.max(1, (source.width * scale).round());
    final height = math.max(1, (source.height * scale).round());
    final size = Size(width.toDouble(), height.toDouble());
    final recorder = ui.PictureRecorder();
    try {
      paint(
        Canvas(recorder),
        size,
        image: source,
        ambient: ambient,
        time: time,
      );
    } catch (_) {
      recorder.endRecording().dispose();
      rethrow;
    }
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// Releases the reusable shader. Views do not dispose their shared renderer.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _shader.dispose();
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('EffectRenderer has been disposed.');
  }
}

double _control(double value, double fallback) =>
    value.isFinite ? value.clamp(0.0, 1.0) : fallback;

/// A signed contextual lane. Nonfinite values fall back to the neutral zero.
double _signed(double value) => value.isFinite ? value.clamp(-1.0, 1.0) : 0;

/// The chroma allowance never drops below the floor and never exceeds one.
double _chroma(double value) => value.isFinite ? value.clamp(0.65, 1.0) : 1;

/// The orientation axis is a unit vector. An invalid or degenerate vector
/// falls back to the neutral (1, 0), which means "no rotation".
Offset _axis(double x, double y) {
  if (!x.isFinite || !y.isFinite) return const Offset(1, 0);
  final length = math.sqrt(x * x + y * y);
  if (length < 1e-6) return const Offset(1, 0);
  return Offset(x / length, y / length);
}

Offset _trailDirection(double x, double y) {
  if (!x.isFinite || !y.isFinite) return Offset.zero;
  final largest = math.max(x.abs(), y.abs());
  if (largest == 0) return Offset.zero;
  final scaledX = x / largest;
  final scaledY = y / largest;
  final length = math.sqrt(scaledX * scaledX + scaledY * scaledY);
  // Fade an uncertain direction through zero instead of flipping a full trail
  // when a smoothed sensor vector reverses. Ordinary vectors stay unit length.
  final strength = largest < 0.05
      ? (largest / 0.05 * length).clamp(0.0, 1.0)
      : 1.0;
  return Offset(scaledX / length * strength, scaledY / length * strength);
}
