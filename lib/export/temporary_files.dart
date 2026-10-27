import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../debug/redact_paths.dart';

/// The prefix of the files that the app writes in the cache.
const String temporaryFilePrefix = 'sonoglitch_';

/// Removes the files that the app left in the cache and that are old.
///
/// The working pictures and the diagnostic reports are written in the cache
/// of the system. The ones that were not deleted, because the app was
/// closed while they were in use, are removed after a day.
///
/// [directory] is where the files are looked for, the cache of the app when
/// it is null. [now] is the moment the age is measured from.
Future<int> removeStaleTemporaryFiles({
  Duration maxAge = const Duration(hours: 24),
  Directory? directory,
  DateTime? now,
}) async {
  final Directory cache;
  try {
    cache = directory ?? await getTemporaryDirectory();
  } catch (error) {
    // The cache is not reachable: there is nothing to remove.
    return 0;
  }
  final cutoff = (now ?? DateTime.now()).subtract(maxAge);
  var removed = 0;
  try {
    for (final entity in cache.listSync()) {
      if (entity is! File) continue;
      if (!fileName(entity.path).startsWith(temporaryFilePrefix)) continue;
      final modified = entity.lastModifiedSync();
      if (modified.isAfter(cutoff)) continue;
      entity.deleteSync();
      removed++;
    }
  } catch (error) {
    // A file that cannot be removed is left behind: the system cleans the
    // cache on its own.
  }
  return removed;
}
