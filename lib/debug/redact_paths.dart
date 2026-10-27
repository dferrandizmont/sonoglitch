/// The name of a path, without the directories that lead to it.
///
/// The logs and the reports must not carry the paths of the device, so only
/// the name of the file is kept.
String fileName(String path) {
  final parts = path.split(RegExp(r'[/\\]'));
  for (var index = parts.length - 1; index >= 0; index--) {
    final part = parts[index];
    if (part.isNotEmpty) return part;
  }
  return path;
}

/// The absolute paths of a text, replaced by the name of their file.
///
/// The logs are shared with the user and the reports are published, so the
/// paths of the device are removed: they say nothing useful and they tell
/// where the user keeps the pictures.
///
/// A path is a drive and a separator, or a separator and at least two parts.
/// Anything else, a word with a slash in the middle or a link, is left alone.
String redactPaths(String text) {
  if (!text.contains('/') && !text.contains('\\')) return text;
  return text.replaceAllMapped(_absolutePath, (match) {
    return fileName(match.group(0)!);
  });
}

/// The absolute paths of a text.
///
/// A path does not start in the middle of a word, of a link or of another
/// path.
final RegExp _absolutePath = RegExp(
  r'''(?<![A-Za-z0-9_:/])(?:(?:[A-Za-z]:[\\/][^\s'";,)\]]+)|(?:/(?:[^\s'";,)\]/]+/)+[^\s'";,)\]]*))''',
);
