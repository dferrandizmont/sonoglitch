import 'capture_result.dart';

/// In-flight work keeps its own capture alive across widget replacements.
class ResultCaptureLease {
  ResultCaptureLease(this.result, this.onReleased);
  final CaptureResult result;
  final void Function()? onReleased;
  int pending = 0;
  bool retired = false;
  bool released = false;

  void retire() {
    retired = true;
    releaseIfIdle();
  }

  void releaseIfIdle() {
    if (!retired || pending != 0 || released) return;
    released = true;
    if (result.source == null) result.rendered.dispose();
    onReleased?.call();
  }
}
