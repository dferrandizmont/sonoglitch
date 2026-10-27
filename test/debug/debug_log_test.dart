import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/debug/debug_log.dart';

void main() {
  group('DebugLog', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('sonoglitch_log_test');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        try {
          await directory.delete(recursive: true);
        } catch (_) {
          // Windows keeps the file locked for a moment; it does not matter
          // for the test.
        }
      }
    });

    test('keeps the lines in memory', () async {
      final log = DebugLog(directory: directory);
      await log.init();
      log.info('test', 'hello');
      expect(log.recentLines, hasLength(1));
      expect(log.recentLines.first, contains('INFO'));
      expect(log.recentLines.first, contains('hello'));
    });

    test('writes the lines in the file', () async {
      final log = DebugLog(directory: directory);
      await log.init();
      log.info('test', 'hello');
      log.error('test', 'boom', StateError('bad'));
      await log.flush();

      final content = await log.readCurrentFile();
      expect(content, contains('INFO test hello'));
      expect(content, contains('ERROR test boom'));
      // The time comes first, in the ISO format of the year.
      expect(content, matches(RegExp(r'^\d{4}-\d{2}-\d{2}T')));
    });

    test('the ring of lines is bounded', () async {
      final log = DebugLog(directory: directory, ringSize: 10);
      await log.init();
      for (var i = 0; i < 50; i++) {
        log.info('test', 'line $i');
      }
      expect(log.recentLines, hasLength(10));
      expect(log.recentLines.last, contains('line 49'));
    });

    test('the file is rotated when it is too big', () async {
      final log = DebugLog(directory: directory, maxFileSize: 512, maxFiles: 3);
      await log.init();
      for (var i = 0; i < 200; i++) {
        log.info('test', 'a line that makes the file grow $i');
      }
      await log.flush();

      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.contains('sonoglitch.log'))
          .toList();
      expect(files.length, greaterThan(1));
      expect(files.length, lessThanOrEqualTo(3));
    });
  });
}
