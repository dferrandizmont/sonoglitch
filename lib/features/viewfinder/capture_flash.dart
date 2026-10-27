import 'package:flutter/material.dart';

/// The short flash that confirms that the picture was taken.
///
/// The flash goes from white to transparent in a fraction of a second, so
/// it never gets in the way of the preview. It does not take the touches:
/// the shutter is the only thing that can be pressed while it is on.
class CaptureFlash extends StatelessWidget {
  const CaptureFlash({super.key, required this.opacity});

  /// How bright the flash is, from 0 to 1.
  final Animation<double> opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: opacity,
        child: const ColoredBox(color: Color(0x66FFFFFF)),
      ),
    );
  }
}
