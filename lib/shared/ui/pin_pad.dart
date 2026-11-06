/// A 4-digit PIN as on a phone's lock screen: four dots over a 3×4 keypad.
/// The fourth digit hands the PIN over by itself; [PinPadState.fail] shakes
/// and clears it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/bloom_theme.dart';
import '../../app/theme/tokens.dart';
import '../../core/l10n/l10n.dart';
import '../../core/profiles/profiles.dart' show kPinLength;
import 'bloom_icon.dart';
import 'pressable.dart';

class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onEntered,
    this.locked = false,
    this.extraKey,
  });

  /// The four digits, once the last one shows.
  final ValueChanged<String> onEntered;

  /// A wait after too many wrong ones, or a check under way: no input.
  final bool locked;

  /// The bottom-left key: a fingerprint, when there is one to offer.
  final Widget? extraKey;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  static const double _key = 76;
  static const double _gap = 22;

  String _pin = '';
  Timer? _handOver;
  Timer? _clearLater;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  void clear() {
    _clearLater?.cancel();
    setState(() => _pin = '');
  }

  void fail() {
    HapticFeedback.heavyImpact();
    _shake.forward(from: 0);
    _clearLater?.cancel();
    _clearLater = Timer(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _pin = '');
    });
  }

  bool get _busy => widget.locked || (_clearLater?.isActive ?? false);

  void _press(String d) {
    if (_busy || _pin.length >= kPinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == kPinLength) {
      // The last dot is seen filled before the check runs.
      _handOver = Timer(const Duration(milliseconds: 90), () {
        if (mounted) widget.onEntered(_pin);
      });
    }
  }

  void _back() {
    if (_busy || _pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  void dispose() {
    _handOver?.cancel();
    _clearLater?.cancel();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    final keys = [
      for (final d in const ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
        _digit(d),
      widget.extraKey == null
          ? const SizedBox(width: _key, height: _key)
          : SizedBox(width: _key, height: _key, child: widget.extraKey),
      _digit('0'),
      _erase(context),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _shake,
          // A damped wave: three swings dying out.
          builder: (context, child) => Transform.translate(
            offset: Offset(
              10 * math.sin(_shake.value * math.pi * 6) * (1 - _shake.value),
              0,
            ),
            child: child,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < kPinLength; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < _pin.length ? t.text : Colors.transparent,
                      border: i < _pin.length
                          ? null
                          : Border.all(
                              color: t.text.withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 36),
        AnimatedOpacity(
          opacity: widget.locked ? 0.4 : 1,
          duration: const Duration(milliseconds: 160),
          child: SizedBox(
            width: 3 * _key + 2 * _gap,
            child: Wrap(spacing: _gap, runSpacing: 14, children: keys),
          ),
        ),
      ],
    );
  }

  Widget _digit(String d) {
    final t = context.bloom;
    return Pressable(
      scale: 0.92,
      onTap: () => _press(d),
      child: Semantics(
        button: true,
        label: d,
        child: Container(
          width: _key,
          height: _key,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: t.pill),
          child: Text(
            d,
            style: bloomText(size: 28, weight: 400, color: t.text),
          ),
        ),
      ),
    );
  }

  Widget _erase(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      scale: 0.92,
      onTap: _back,
      child: Semantics(
        button: true,
        label: context.l.pinErase,
        child: SizedBox(
          width: _key,
          height: _key,
          child: Center(
            child: BloomIcon(Bi.backspace, size: 26, color: t.text2),
          ),
        ),
      ),
    );
  }
}
