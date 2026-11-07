/// Settings → Profile: the PIN (a lock on the way in), the fingerprint in its
/// place, signing out to the profile choice, deleting the profile. The list of
/// profiles is only on the gate.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/session.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/profiles/bio.dart';
import '../../../core/profiles/profiles.dart';
import '../../../core/store/library_store.dart';
import '../../../shared/ui/bloom_icon.dart';
import '../../../shared/ui/bloom_sheet.dart';
import '../../../shared/ui/bloom_toast.dart';
import '../../../shared/ui/danger_confirm.dart';
import '../../../shared/ui/pin_pad.dart';
import '../../../shared/ui/soft_text.dart';
import '../../../shared/ui/subpage_header.dart';
import '../../library/local_tracks.dart';
import 'settings_rows.dart';

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  Profiles get _profiles => Profiles.instance;

  late bool _locked = _profiles.locked;
  late bool _bio = _profiles.bioOn;

  /// The phone has a fingerprint or face to offer; until it says, no row.
  bool _bioAvailable = false;

  @override
  void initState() {
    super.initState();
    bioAvailable().then((ok) {
      if (mounted) setState(() => _bioAvailable = ok);
    });
  }

  void _reread() => setState(() {
    _locked = _profiles.locked;
    _bio = _profiles.bioOn;
  });

  Future<void> _pin(_PinMode mode) async {
    final l = context.l;
    final done = await _showPinSheet(context, mode);
    if (!done || !mounted) return;
    _reread();
    toaster.show(switch (mode) {
      _PinMode.set => l.profToastSet,
      _PinMode.change => l.profToastChanged,
      _ => l.profToastRemoved,
    }, kind: ToastKind.success);
  }

  Future<void> _delete() async {
    final l = context.l;
    final bool yes;
    if (_locked) {
      yes = await _showPinSheet(context, _PinMode.delete);
    } else {
      yes = await confirmDanger(
        context,
        icon: Bi.trashBinTrash,
        title: l.profDeleteConfirm,
        body: l.profDeleteBody,
        button: l.commonDelete,
      );
    }
    if (!yes) return;
    // Before the library goes with the folder: the system lends a limited
    // number of permissions to the user's own files, and they must be given
    // back.
    await forgetLocalTracks(ref.read(libraryProvider).tracks.values);
    await leaveProfile(remove: true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.bloom;

    return SubPage(
      title: l.setProfile,
      onBack: () => context.go('/settings'),
      children: [
        SettingsCaption(l.profEntry),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            if (!_locked)
              SettingsLinkRow(
                icon: Bi.lockKeyholeMinimalistic,
                title: l.profPinSet,
                subtitle: l.profPinOff,
                onTap: () => _pin(_PinMode.set),
              )
            else ...[
              SettingsLinkRow(
                icon: Bi.lockKeyholeMinimalistic,
                title: l.profPinChange,
                subtitle: l.profPinOn,
                onTap: () => _pin(_PinMode.change),
              ),
              SettingsLinkRow(
                icon: Bi.lockKeyholeMinimalistic,
                title: l.profPinRemove,
                subtitle: l.profPinRemoveSub,
                onTap: () => _pin(_PinMode.remove),
              ),
            ],
            // Only over a PIN: it stands in for one.
            if (_locked && _bioAvailable)
              SettingsToggleRow(
                icon: Bi.faceScanCircle,
                title: l.profBioTitle,
                subtitle: l.profBioSub,
                value: _bio,
                onChanged: (on) async {
                  // Turning it on is proved by the finger itself: a phone
                  // with someone else's enrolled would otherwise slip in.
                  if (on && !await bioAsk(l.profBioConfirm)) return;
                  _profiles.setBio(on);
                  _reread();
                },
              ),
            SettingsLinkRow(
              icon: Bi.logout2,
              title: l.profSignOutTitle,
              subtitle: l.profSignOutSub,
              onTap: () => leaveProfile(),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            BloomIcon(Bi.dangerTriangle, size: 13, color: t.danger),
            const SizedBox(width: 6),
            SettingsCaption(l.sysDangerZone),
          ],
        ),
        const SizedBox(height: 10),
        SettingsGroupCard(
          dividerInset: 52,
          rows: [
            SettingsLinkRow(
              icon: Bi.trashBinTrash,
              title: l.profDeleteTitle,
              subtitle: l.profDeleteSub,
              danger: true,
              onTap: _delete,
            ),
          ],
        ),
      ],
    );
  }
}

/// `set` (new, repeat), `change` (current, new, repeat), `remove` (current),
/// `delete` (current, then the profile goes).
enum _PinMode { set, change, remove, delete }

enum _Step { current, fresh, repeat }

/// The PIN step by step on one keypad. True when it went through: the PIN is
/// set, changed or removed, or (delete) the right one was typed.
Future<bool> _showPinSheet(BuildContext context, _PinMode mode) async =>
    await showBloomSheetChild<bool>(
      context: context,
      scrolls: false,
      child: _PinSheet(mode: mode),
    ) ==
    true;

class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.mode});

  final _PinMode mode;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final GlobalKey<PinPadState> _pad = GlobalKey();

  late final List<_Step> _steps = switch (widget.mode) {
    _PinMode.set => const [_Step.fresh, _Step.repeat],
    _PinMode.change => const [_Step.current, _Step.fresh, _Step.repeat],
    _ => const [_Step.current],
  };
  int _at = 0;
  String? _current;
  String? _fresh;
  String _error = '';
  bool _busy = false;

  _Step get _step => _steps[_at];

  Future<void> _take(String pin) async {
    final l = context.l;
    setState(() => _error = '');
    switch (_step) {
      case _Step.current:
        setState(() => _busy = true);
        final ok = await Profiles.instance.checkPin(pin);
        if (!mounted) return;
        setState(() => _busy = false);
        if (!ok) {
          setState(() => _error = l.gateWrong);
          _pad.currentState?.fail();
          return;
        }
        _current = pin;
      case _Step.fresh:
        _fresh = pin;
      case _Step.repeat:
        if (pin != _fresh) {
          setState(() {
            _error = l.pinMismatch;
            _at = _steps.indexOf(_Step.fresh);
          });
          _pad.currentState?.fail();
          return;
        }
    }
    _pad.currentState?.clear();
    if (_at + 1 < _steps.length) {
      setState(() => _at++);
    } else {
      await _finish();
    }
  }

  Future<void> _finish() async {
    if (widget.mode == _PinMode.delete) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = true);
    final ok = await Profiles.instance.setPin(
      _current,
      widget.mode == _PinMode.remove ? null : _fresh,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final deleting = widget.mode == _PinMode.delete;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SoftText(
            // The step's question; deleting keeps its own.
            deleting
                ? l.profDeleteConfirm
                : switch (_step) {
                    _Step.current => l.pinCurrent,
                    _Step.fresh => l.pinNew,
                    _Step.repeat => l.pinRepeat,
                  },
            textAlign: TextAlign.center,
            style: theme.titleLarge,
          ),
          if (deleting) ...[
            const SizedBox(height: 8),
            Text(
              l.profDeleteBody,
              textAlign: TextAlign.center,
              style: theme.bodyMedium?.copyWith(color: t.text2, height: 1.35),
            ),
          ],
          SizedBox(
            height: 44,
            child: Center(
              child: SoftText(
                _error,
                style: theme.bodySmall?.copyWith(color: t.danger),
              ),
            ),
          ),
          PinPad(key: _pad, locked: _busy, onEntered: _take),
        ],
      ),
    );
  }
}
