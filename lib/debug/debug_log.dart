import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'redact_paths.dart';

/// Severity of a log line.
enum LogLevel {
  info('INFO'),
  warning('WARN'),
  error('ERROR');

  const LogLevel(this.label);

  /// The text written in the log file.
  final String label;
}

/// A small file logger with an in memory ring buffer.
///
/// The file lives in the documents directory of the app, so the user can
/// share it from the settings screen. It rotates at 512 KB and keeps three
/// files. The last lines are also kept in memory, which is what the debug
/// panel shows.
///
/// PRIVACY: only technical information is written. No audio, no personal
/// data and no user content ever reaches the log.
class DebugLog {
  /// Creates a logger.
  ///
  /// [directory] is where the log file is written; when it is null the
  /// documents directory of the app is used.
  DebugLog({
    this.directory,
    this.maxFileSize = 512 * 1024,
    this.maxFiles = 3,
    this.ringSize = 300,
  });

  /// Maximum size of the log file before it is rotated.
  final int maxFileSize;

  /// How many files are kept: the current one and two older ones.
  final int maxFiles;

  /// How many lines are kept in memory.
  final int ringSize;

  /// Where the log file is written, null for the documents directory.
  final Directory? directory;

  final Queue<String> _ring = Queue<String>();

  File? _file;
  Future<void> _pending = Future<void>.value();

  /// The lines kept in memory, oldest first.
  List<String> get recentLines => List<String>.unmodifiable(_ring);

  /// The file the lines are written to, if the logger could be opened.
  File? get file => _file;

  /// Opens the log file and creates the directory when needed.
  ///
  /// Failing to open the file is not fatal: the logger keeps working in
  /// memory only.
  Future<void> init() async {
    final directory = this.directory ?? await _defaultDirectory();
    if (directory == null) return;
    try {
      await directory.create(recursive: true);
      final file = File(
        '${directory.path}${Platform.pathSeparator}sonoglitch.log',
      );
      if (!file.existsSync()) {
        await file.writeAsString('');
      }
      _file = file;
    } catch (error) {
      _file = null;
      debugPrint('DebugLog: cannot open the log file: $error');
    }
  }

  /// Writes an informational line.
  void info(String tag, String message) => log(LogLevel.info, tag, message);

  /// Writes a warning line.
  void warning(String tag, String message) =>
      log(LogLevel.warning, tag, message);

  /// Writes an error line, with the optional error and stack trace.
  void error(
    String tag,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    var text = message;
    if (error != null) text = '$message: $error';
    log(LogLevel.error, tag, text);
    if (stackTrace != null && error != null) {
      log(
        LogLevel.error,
        tag,
        stackTrace.toString().trim().replaceAll('\n', ' | '),
      );
    }
  }

  /// Writes a line with an explicit [level].
  ///
  /// The paths of the device are removed: the log is shared with the user
  /// and it must not tell where the files of the app are.
  void log(LogLevel level, String tag, String message) {
    final line =
        '${DateTime.now().toIso8601String()} '
        '${level.label} $tag ${redactPaths(message)}';
    _ring.addLast(line);
    while (_ring.length > ringSize) {
      _ring.removeFirst();
    }
    final file = _file;
    if (file == null) return;
    _pending = _pending.then((_) async {
      try {
        await file.writeAsString('$line\n', mode: FileMode.append);
        await _rotateIfNeeded(file);
      } catch (error) {
        debugPrint('DebugLog: cannot write the log file: $error');
      }
    });
  }

  /// Waits until every pending line has been written to the file.
  Future<void> flush() => _pending;

  /// The whole content of the current log file.
  Future<String> readCurrentFile() async {
    final file = _file;
    if (file == null || !file.existsSync()) return '';
    try {
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  /// The last [count] lines, as a single string.
  String tail(int count) {
    final lines = _ring.toList();
    if (lines.length <= count) return lines.join('\n');
    return lines.sublist(lines.length - count).join('\n');
  }

  Future<void> _rotateIfNeeded(File file) async {
    if (!file.existsSync()) return;
    final length = await file.length();
    if (length < maxFileSize) return;

    final base = file.path;
    final oldest = '$base.${maxFiles - 1}';
    if (File(oldest).existsSync()) {
      await File(oldest).delete();
    }
    for (var index = maxFiles - 2; index >= 1; index--) {
      final source = File('$base.$index');
      if (source.existsSync()) {
        await source.rename('$base.${index + 1}');
      }
    }
    await file.rename('$base.1');
    await file.create();
  }

  Future<Directory?> _defaultDirectory() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return directory;
    } catch (error) {
      debugPrint('DebugLog: no documents directory: $error');
      return null;
    }
  }
}
