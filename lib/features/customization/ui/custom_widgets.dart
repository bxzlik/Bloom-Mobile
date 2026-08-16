/// Общее для страниц кастомизации: каркас с кнопками внизу, широкая кнопка,
/// поле в шторке и подпись пустого списка.
///
/// Своё, а не [SubPage]: там всё содержимое едет одним списком, а здесь снизу
/// стоят прибитые кнопки («Добавить по URL» / «Загрузить», «Создать пресет» /
/// «Импорт») — так их показал пользователь на макете.
library;

import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/glass.dart';
import '../../../shared/ui/subpage_header.dart';

/// Страница раздела: шапка сверху, содержимое посередине, кнопки снизу.
class CustomizationPage extends StatelessWidget {
  const CustomizationPage({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final VoidCallback onBack;
  final Widget child;

  /// Кнопки, прибитые к низу экрана — над барами каркаса.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SubPageHeader(title: title, onBack: onBack),
          ),
          const SizedBox(height: 10),
          Expanded(child: child),
          if (actions.isNotEmpty)
            Padding(
              // Снизу — запас под миниплеер и таб-бар: они плавают поверх
              // содержимого, и кнопка под ними была бы недоступна.
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                12 + bottomBarsInset(context),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    actions[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Широкая кнопка внизу страницы: значок и подпись по центру.
class WideButton extends StatelessWidget {
  const WideButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Опасное действие — красная подпись и красноватая плашка, как в шторках.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final color = danger ? t.sysFavIco : t.text;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: GlassBox(
        // Опасная кнопка красная и в стекле: её цвет — сигнал, а не
        // поверхность темы, поэтому прозрачной она не становится.
        color: danger ? t.sysFavTint : null,
        enabled: !danger,
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Подпись на месте пустого списка — десктопные `.ssub` по центру.
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 40),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  );
}

/// Поле ввода в шторке — ровно то же, что у «Создать плейлист» ([SheetField]):
/// широкое поле и акцентная галочка, которая появляется вместе с текстом.
///
/// Возвращает введённое значение через `Navigator.pop`.
class SheetTextField extends StatefulWidget {
  const SheetTextField({
    super.key,
    required this.hint,
    this.initial = '',
    this.maxLength,
  });

  final String hint;
  final String initial;
  final int? maxLength;

  @override
  State<SheetTextField> createState() => _SheetTextFieldState();
}

class _SheetTextFieldState extends State<SheetTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => SheetField(
    controller: _controller,
    hint: widget.hint,
    autofocus: true,
    maxLength: widget.maxLength,
    onChanged: (_) => setState(() {}),
    onSubmit: _submit,
  );
}
