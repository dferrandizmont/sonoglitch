/// The shapes the exported photo can take.
enum ExportFormat {
  /// The picture as it was taken.
  original,

  /// A square crop of the centre.
  square,

  /// A vertical 4:5 crop of the centre.
  portrait,

  /// A vertical 9:16 crop of the centre, for the stories.
  story;

  /// The width over height of the format, or null for [ExportFormat.original].
  double? get aspectRatio {
    switch (this) {
      case ExportFormat.original:
        return null;
      case ExportFormat.square:
        return 1;
      case ExportFormat.portrait:
        return 4 / 5;
      case ExportFormat.story:
        return 9 / 16;
    }
  }
}
