import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/ambient/ambient_state.dart';
import 'package:sonoglitch/camera/camera_metrics.dart';
import 'package:sonoglitch/debug/capture_timings.dart';
import 'package:sonoglitch/debug/debug_log.dart';
import 'package:sonoglitch/debug/device_summary.dart';
import 'package:sonoglitch/debug/diagnostic_report.dart';
import 'package:sonoglitch/debug/redact_paths.dart';

void main() {
  group('redactPaths', () {
    test('the name of the file is kept', () {
      expect(
        redactPaths('/data/user/0/com.sonoglitch/cache/sonoglitch_1.png'),
        'sonoglitch_1.png',
      );
    });

    test('the path of windows is kept', () {
      expect(
        redactPaths(r'C:\Users\Someone\AppData\sonoglitch.log'),
        'sonoglitch.log',
      );
    });

    test('the path inside a sentence is kept', () {
      expect(
        redactPaths(
          "cannot open '/data/user/0/com.sonoglitch/files/sonoglitch.log' "
          '(OS Error: 2)',
        ),
        "cannot open 'sonoglitch.log' (OS Error: 2)",
      );
    });

    test('a text without paths is not changed', () {
      expect(
        redactPaths('the camera did not start'),
        'the camera did not start',
      );
      expect(redactPaths('noise 0.42'), 'noise 0.42');
    });

    test('a word with a slash is not a path', () {
      expect(redactPaths('and/or'), 'and/or');
    });

    test('a link is not a path', () {
      expect(
        redactPaths('see https://example.com/docs for more'),
        'see https://example.com/docs for more',
      );
    });
  });

  group('DebugLog', () {
    test('the log file does not carry the paths of the device', () async {
      final directory = Directory.systemTemp.createTempSync('sonoglitch_log');
      addTearDown(() {
        try {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        } catch (_) {
          // The directory is left behind in the cache of the system.
        }
      });
      final log = DebugLog(directory: directory);
      await log.init();

      log.info(
        'export',
        'picture written to '
            '/data/user/0/com.sonoglitch/cache/sonoglitch_1.png',
      );
      await log.flush();

      final content = await log.readCurrentFile();
      expect(content, contains('sonoglitch_1.png'));
      expect(content, isNot(contains('/data/user')));
    });
  });

  group('DiagnosticReport', () {
    test('the report does not carry the paths of the device', () {
      final report = DiagnosticReport.build(
        ambient: AmbientState.calm,
        metrics: const CameraMetricsData(),
        styleId: 'static',
        timings: const CaptureTimings(),
        device: const DeviceSummary(
          model: 'test',
          systemVersion: 'test',
          platform: 'test',
        ),
        appVersion: '0.1.0',
        buildMode: 'debug',
        logs: <String>[
          'the picture is in /data/user/0/com.sonoglitch/cache/sonoglitch_1.png',
        ],
      );

      final json = DiagnosticReport.encode(report);
      expect(json, contains('sonoglitch_1.png'));
      expect(json, isNot(contains('/data/user')));
    });
  });
}
