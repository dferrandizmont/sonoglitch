import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'debug_log.dart';
import 'diagnostic_report.dart';

/// Writes the diagnostic report to a file and shares it with the log.
class DiagnosticExporter {
  DiagnosticExporter({required this.log});

  /// The logger whose file is shared next to the report.
  final DebugLog log;

  /// Writes the report as JSON in the temporary directory.
  Future<File> writeReport(Map<String, Object?> report) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}sonoglitch_report.json',
    );
    await file.writeAsString(DiagnosticReport.encode(report), flush: true);
    return file;
  }

  /// Shares the JSON report and the log file.
  Future<void> share(Map<String, Object?> report, {Rect? origin}) async {
    final reportFile = await writeReport(report);
    final files = <XFile>[XFile(reportFile.path)];
    final logFile = log.file;
    if (logFile != null && logFile.existsSync()) {
      files.add(XFile(logFile.path));
    }
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        subject: 'Sonoglitch diagnostics',
        sharePositionOrigin: origin,
      ),
    );
  }
}
