/// Words that change softly: the old ones fade out as the new ones fade in.
/// An empty text fades out, so a line of notes can come and go.
library;

import 'package:flutter/material.dart';

class SoftText extends StatelessWidget {
  const SoftText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 200),
    switchInCurve: Curves.easeOutQuad,
    switchOutCurve: Curves.easeInQuad,
    child: Text(
      text,
      key: ValueKey(text),
      style: style,
      textAlign: textAlign,
    ),
  );
}
