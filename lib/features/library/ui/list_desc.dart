/// A playlist's description in its header: one line, and a tap on a cut one
/// opens the whole of it in a sheet.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/pressable.dart';

class ListDescLine extends StatelessWidget {
  const ListDescLine({
    super.key,
    required this.text,
    required this.title,
    this.cover,
  });

  final String text;

  /// The playlist's name and picture, for the sheet's header.
  final String title;
  final String? cover;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: context.bloom.text2.withValues(alpha: 0.8),
    );
    return LayoutBuilder(
      builder: (context, box) {
        // I measure it myself: Text doesn't say whether it was cut.
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: box.maxWidth);
        final cut = painter.didExceedMaxLines;
        painter.dispose();

        final line = Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
        if (!cut) return line;
        return Pressable(
          scale: 0.98,
          onTap: () => showListDescSheet(
            context,
            text: text,
            title: title,
            cover: cover,
          ),
          child: line,
        );
      },
    );
  }
}

Future<void> showListDescSheet(
  BuildContext context, {
  required String text,
  required String title,
  String? cover,
}) {
  final theme = Theme.of(context).textTheme;
  return showBloomSheetChild<void>(
    context: context,
    header: SheetHero(
      cover: cover,
      title: title,
      subtitle: context.l.tiDescription,
    ),
    child: SheetPanel(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Text(
            text.trim(),
            style: theme.bodyLarge?.copyWith(
              fontSize: 15,
              height: 1.4,
              color: context.bloom.text.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    ),
  );
}
