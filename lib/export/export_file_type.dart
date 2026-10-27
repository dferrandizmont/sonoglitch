/// The type of the file that is written.
///
/// The name of the type is the one of the settings, so the file that is
/// saved in the gallery and the file that is shared carry the extension of
/// the type the user chose.
enum ExportFileType {
  /// A lossless PNG. The default: every exported pixel is kept.
  png,

  /// A JPEG of quality 95, encoded by the native encoder of the phone.
  jpeg;

  /// The extension of the files of this type.
  String get extension => switch (this) {
    ExportFileType.png => '.png',
    ExportFileType.jpeg => '.jpg',
  };
}
