import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/camera/camera_metrics.dart';
import 'package:sonoglitch/debug/capture_timings.dart';
import 'package:sonoglitch/debug/device_summary.dart';
import 'package:sonoglitch/debug/diagnostic_report.dart';

void main() {
  group('the diagnostic report', () {
    test('has every measurement of the panel', () {
      final report = DiagnosticReport.build(
        ambient: const AmbientState(noise: 0.5, light: 0.25, motion: 0.75),
        metrics: const CameraMetricsData(fps: 24, conversionMs: 3),
        styleId: 'static',
        timings: const CaptureTimings(takeMs: 120, decodeMs: 30),
        device: const DeviceSummary(
          model: 'Pixel',
          systemVersion: 'Android 16',
          platform: 'Android',
        ),
        appVersion: '0.1.0',
        buildMode: 'debug',
        logs: const ['one line'],
      );

      expect(report['appVersion'], '0.1.0');
      expect(report['buildMode'], 'debug');
      expect(report['style'], 'static');
      expect((report['ambient'] as Map)['noise'], 0.5);
      expect((report['camera'] as Map)['fps'], 24);
      expect((report['lastCapture'] as Map)['takeMs'], 120);
      expect((report['device'] as Map)['model'], 'Pixel');
      expect(report['logs'], ['one line']);
    });

    test('is encoded as JSON', () {
      final json = DiagnosticReport.encode({'a': 1});
      expect(json, contains('"a": 1'));
    });

    test('carries the readings of the new sensors', () {
      final report = DiagnosticReport.build(
        ambient: const AmbientState(
          noise: 0.5,
          light: 0.25,
          motion: 0.75,
          rawLux: 320,
          baselineDb: 65,
          burst: 0.4,
          bass: 0.1,
          mid: 0.2,
          treble: 0.3,
          seed: 0.4,
        ),
        metrics: const CameraMetricsData(fps: 24, conversionMs: 3),
        styleId: 'static',
        timings: const CaptureTimings(takeMs: 120, decodeMs: 30),
        device: const DeviceSummary(
          model: 'Pixel',
          systemVersion: 'Android 16',
          platform: 'Android',
        ),
        appVersion: '0.1.0',
        buildMode: 'debug',
        logs: const ['one line'],
      );

      final ambient = report['ambient'] as Map;
      expect(ambient['rawLux'], 320);
      expect(ambient['baselineDb'], 65);
      expect(ambient['burst'], 0.4);
      expect(ambient['bass'], 0.1);
      expect(ambient['mid'], 0.2);
      expect(ambient['treble'], 0.3);
      expect(ambient, isNot(contains('seed')));
      expect(ambient, isNot(contains('signature')));
      expect(ambient, isNot(contains('photoId')));
    });
  });
}
