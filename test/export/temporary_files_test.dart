import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sonoglitch/export/temporary_files.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sonoglitch_cache');
  });

  tearDown(() {
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } catch (_) {
      // The directory is left behind in the cache of the system.
    }
  });

  File write(String name, DateTime modified) {
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    file.writeAsStringSync('x');
    file.setLastModifiedSync(modified);
    return file;
  }

  test('the old files of the app are removed', () async {
    final now = DateTime(2026, 10, 24, 12);
    final old = write(
      'sonoglitch_1.png',
      now.subtract(const Duration(hours: 30)),
    );
    final fresh = write(
      'sonoglitch_2.png',
      now.subtract(const Duration(hours: 2)),
    );
    final other = write('other.png', now.subtract(const Duration(hours: 30)));

    final removed = await removeStaleTemporaryFiles(
      directory: directory,
      now: now,
    );

    expect(removed, 1);
    expect(old.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(other.existsSync(), isTrue);
  });

  test('the report of the diagnostics is removed too', () async {
    final now = DateTime(2026, 10, 24, 12);
    final report = write(
      'sonoglitch_report.json',
      now.subtract(const Duration(days: 2)),
    );

    await removeStaleTemporaryFiles(directory: directory, now: now);

    expect(report.existsSync(), isFalse);
  });

  test('a cache that cannot be read removes nothing', () async {
    final missing = Directory('${directory.path}${Platform.pathSeparator}none');
    final removed = await removeStaleTemporaryFiles(directory: missing);
    expect(removed, 0);
  });
}
