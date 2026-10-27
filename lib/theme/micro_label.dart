import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Uppercase instrument label, with optional role colour and size overrides.
class MicroLabel extends StatelessWidget {
  const MicroLabel(
    this.text, {
    super.key,
    this.color,
    this.fontSize,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  final String text;
  final Color? color;
  final double? fontSize;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: AppTheme.micro.copyWith(color: color, fontSize: fontSize),
    maxLines: maxLines,
    overflow: overflow,
    textAlign: textAlign,
  );
}
