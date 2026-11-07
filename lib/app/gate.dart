/// The gate: Bloom with only the profiles in it, before any is open. Who's
/// listening (the list), a locked one's PIN or fingerprint, a new profile.
/// It looks as the last profile did and writes nothing there.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../core/profiles/bio.dart';
import '../core/profiles/profiles.dart';
import '../core/store/settings_store.dart';
import '../features/profile/ui/image_cropper.dart';
import '../features/profile/ui/profile_avatar.dart';
import '../features/profile/ui/profile_edit_screen.dart' show ProfileField;
import '../features/settings/user_fonts.dart';
import '../shared/ui/atoms.dart';
import '../shared/ui/bloom_icon.dart';
import '../shared/ui/pin_pad.dart';
import '../shared/ui/pressable.dart';
import '../shared/ui/soft_text.dart';
import 'app.dart' show SpringScroll;
import 'theme/bloom_theme.dart';
import 'theme/tokens.dart';

/// Shows the gate through [show] until it gives a profile to open.
Future<String> runGate(
  ProviderContainer container,
  ProfilesStart start,
  void Function(Widget gate) show,
) {
  final done = Completer<String>();
  show(
    UncontrolledProviderScope(
      container: container,
      // The gate stays up while it fades out: a late fingerprint mustn't open twice.
      child: _GateApp(
        start: start,
        onOpen: (id) {
          if (!done.isCompleted) done.complete(id);
        },
      ),
    ),
  );
  return done.future;
}

class _GateApp extends ConsumerWidget {
  const _GateApp({required this.start, required this.onOpen});

  final ProfilesStart start;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: 'Bloom',
      debugShowCheckedModeBanner: false,
      locale: settings.locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      scrollBehavior: const SpringScroll(),
      theme: buildBloomTheme(
        settings.tokens,
        transparentPages: false,
        fontFamily: ref.watch(uiFontProvider),
      ),
      builder: (_, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: systemBarsStyle(settings.tokens),
        child: child ?? const SizedBox(),
      ),
      home: _Gate(start: start, onOpen: onOpen),
    );
  }
}

enum _View { list, pin, forgot, create, offer }

class _Gate extends StatefulWidget {
  const _Gate({required this.start, required this.onOpen});

  final ProfilesStart start;
  final ValueChanged<String> onOpen;

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  Profiles get _profiles => Profiles.instance;

  late _View _view = _View.values.byName(widget.start.view!);
  late String? _pickedId = widget.start.id;
  List<ProfileEntry> _list = const [];

  // The new profile's name and photo wait while its PIN is offered.
  final TextEditingController _nick = TextEditingController();
  Uint8List? _avatar;

  // The PIN screen.
  final GlobalKey<PinPadState> _pad = GlobalKey();
  bool _wrong = false;
  bool _checking = false;
  int _wait = 0;
  Timer? _waitTick;
  bool _bio = false;

  // The new profile's PIN: typed once, waiting for its repeat.
  String? _first;
  bool _mismatch = false;
  bool _making = false;

  ProfileEntry? get _picked =>
      _list.where((p) => p.id == _pickedId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _list = _profiles.list();
    _nick.addListener(() => setState(() {}));
    if (_view == _View.pin) _enterPin();
  }

  @override
  void dispose() {
    _nick.dispose();
    _waitTick?.cancel();
    super.dispose();
  }

  void _go(_View v) {
    if ({_View.create, _View.offer}.contains(_view) &&
        !{_View.create, _View.offer}.contains(v)) {
      _nick.clear();
      _avatar = null;
    }
    setState(() {
      _view = v;
      _first = null;
      _mismatch = false;
      _wrong = false;
    });
    if (v == _View.pin) _enterPin();
  }

  void _pick(ProfileEntry p) {
    _pickedId = p.id;
    if (!p.locked) {
      if (_profiles.open(p.id)) widget.onOpen(p.id);
      return;
    }
    _go(_View.pin);
  }

  String _nameOf(ProfileEntry? p) =>
      p == null || p.name.isEmpty ? context.l.profileDefaultName : p.name;

  // ── The PIN ──

  void _enterPin() {
    _wait = _profiles.waitLeft(_pickedId ?? '');
    _tickWait();
    _bio = false;
    final p = _picked;
    if (p != null && p.bio) {
      bioAvailable().then((ok) {
        if (!mounted || _view != _View.pin || _pickedId != p.id) return;
        setState(() => _bio = ok);
        // Asked at once, as a phone's lock screen does; the PIN stays below.
        if (ok) _askBio();
      });
    }
  }

  void _tickWait() {
    _waitTick?.cancel();
    if (_wait <= 0) return;
    _waitTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _wait = _profiles.waitLeft(_pickedId ?? ''));
      if (_wait <= 0) _waitTick?.cancel();
    });
  }

  Future<void> _askBio() async {
    final p = _picked;
    if (p == null) return;
    final ok = await bioAsk(context.l.gateBioReason(_nameOf(p)));
    if (ok && mounted && _profiles.openByBio(p.id)) widget.onOpen(p.id);
  }

  Future<void> _tryPin(String pin) async {
    final id = _pickedId;
    if (id == null || _checking) return;
    setState(() => _checking = true);
    final r = await _profiles.unlock(id, pin);
    if (!mounted) return;
    setState(() => _checking = false);
    if (r == 0) {
      widget.onOpen(id);
      return;
    }
    setState(() {
      _wrong = r < 0;
      if (r > 0) _wait = r;
    });
    _tickWait();
    _pad.currentState?.fail();
  }

  // ── A new profile ──

  Future<void> _pickAvatar() async {
    final bytes = await pickAndCropBytes(context, shape: CropShape.circle);
    if (bytes != null && mounted) setState(() => _avatar = bytes);
  }

  void _offerPin(String pin) {
    if (_first == null) {
      setState(() {
        _first = pin;
        _mismatch = false;
      });
      _pad.currentState?.clear();
    } else if (pin == _first) {
      _make(pin);
    } else {
      setState(() {
        _first = null;
        _mismatch = true;
      });
      _pad.currentState?.fail();
    }
  }

  Future<void> _make(String? pin) async {
    if (_making) return;
    setState(() => _making = true);
    final id = await _profiles.make(_nick.text, _avatar, pin);
    if (!mounted) return;
    if (id != null) {
      widget.onOpen(id);
    } else {
      setState(() => _making = false);
    }
  }

  // ── Back ──

  _View? get _backTo => switch (_view) {
    _View.list => null,
    _View.pin => _View.list,
    _View.forgot => _View.pin,
    _View.create => _list.isEmpty ? null : _View.list,
    _View.offer => _View.create,
  };

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return PopScope(
      canPop: _backTo == null,
      onPopInvokedWithResult: (didPop, _) {
        final to = _backTo;
        if (!didPop && to != null) _go(to);
      },
      child: Scaffold(
        backgroundColor: t.bg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: KeyedSubtree(
              key: ValueKey(_view),
              child: switch (_view) {
                _View.list => _listView(),
                _View.pin => _pinView(),
                _View.forgot => _forgotView(),
                _View.create => _createView(),
                _View.offer => _offerView(),
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Who's listening ──

  Widget _listView() {
    final t = context.bloom;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Title(context.l.gateTitle),
            const SizedBox(height: 36),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 26,
              children: [
                for (final p in _list)
                  _Tile(
                    label: _nameOf(p),
                    locked: p.locked,
                    onTap: () => _pick(p),
                    face: AvatarFace(image: _fileImage(p.avatar), size: 96),
                  ),
                _Tile(
                  label: context.l.gateAdd,
                  onTap: () => _go(_View.create),
                  face: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.pill,
                    ),
                    child: Center(
                      child: BloomIcon(Bi.add, size: 32, color: t.text2),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── A locked profile's PIN ──

  Widget _pinView() {
    final t = context.bloom;
    final p = _picked;
    final note = _wait > 0
        ? context.l.gateWait(_wait)
        : _wrong
        ? context.l.gateWrong
        : '';
    return _Centered(
      children: [
        AvatarFace(image: _fileImage(p?.avatar), size: 84),
        const SizedBox(height: 14),
        Text(
          _nameOf(p),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        _Note(note),
        PinPad(
          key: _pad,
          locked: _wait > 0 || _checking,
          onEntered: _tryPin,
          extraKey: _bio
              ? Pressable(
                  scale: 0.92,
                  onTap: _askBio,
                  child: Semantics(
                    button: true,
                    label: context.l.profBioTitle,
                    child: Center(
                      child: BloomIcon(
                        Bi.faceScanCircle,
                        size: 28,
                        color: t.text2,
                      ),
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 26),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 22,
          children: [
            if (_list.length > 1)
              _Link(context.l.gateOther, () => _go(_View.list)),
            _Link(context.l.gateForgot, () => _go(_View.forgot)),
          ],
        ),
      ],
    );
  }

  // ── Forgot: the only way out is deleting it ──

  Widget _forgotView() {
    final t = context.bloom;
    final theme = Theme.of(context).textTheme;
    final p = _picked;
    return _Centered(
      children: [
        AvatarFace(image: _fileImage(p?.avatar), size: 76),
        const SizedBox(height: 18),
        Text(
          context.l.gateForgotTitle(_nameOf(p)),
          textAlign: TextAlign.center,
          style: theme.titleLarge,
        ),
        const SizedBox(height: 10),
        Text(
          context.l.gateForgotText,
          textAlign: TextAlign.center,
          style: theme.bodyMedium?.copyWith(color: t.text2, height: 1.35),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: BloomButton(
                label: context.l.commonCancel,
                tone: ButtonTone.plate,
                height: 46,
                onTap: () => _go(_View.pin),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: BloomButton(
                label: context.l.commonDelete,
                tone: ButtonTone.danger,
                height: 46,
                onTap: () {
                  _profiles.forget(_pickedId ?? '');
                  _pickedId = null;
                  _list = _profiles.list();
                  _go(_list.isEmpty ? _View.create : _View.list);
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── A new profile, as signing up: a name and a photo, then a PIN ──

  Widget _createView() {
    final t = context.bloom;
    final ready = _nick.text.trim().isNotEmpty;
    final avatar = _avatar;
    return _Centered(
      children: [
        _Title(_list.isEmpty ? context.l.gateCreateFirst : context.l.gateAdd),
        const SizedBox(height: 28),
        Pressable(
          scale: 0.96,
          onTap: _pickAvatar,
          child: Semantics(
            button: true,
            label: context.l.gatePickAvatar,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AvatarFace(
                  image: avatar == null ? null : MemoryImage(avatar),
                  size: 108,
                ),
                // A small badge says the circle takes a photo.
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.text,
                      border: Border.all(color: t.bg, width: 3),
                    ),
                    child: Center(
                      child: BloomIcon(Bi.gallery, size: 15, color: t.bg),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        ProfileField(
          label: context.l.profileNickname,
          controller: _nick,
          hint: context.l.profileNicknameHint,
          limit: kProfileNameMax,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            if (_list.isNotEmpty) ...[
              Expanded(
                child: BloomButton(
                  label: context.l.commonBack,
                  tone: ButtonTone.plate,
                  height: 46,
                  onTap: () => _go(_View.list),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: BloomButton(
                label: context.l.gateNext,
                tone: ButtonTone.ink,
                height: 46,
                onTap: ready
                    ? () {
                        FocusScope.of(context).unfocus();
                        _go(_View.offer);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── The new profile's PIN: set (twice) or skip ──

  Widget _offerView() {
    final avatar = _avatar;
    return _Centered(
      children: [
        AvatarFace(
          image: avatar == null ? null : MemoryImage(avatar),
          size: 84,
        ),
        const SizedBox(height: 14),
        SoftText(
          _first == null ? context.l.gatePinOffer : context.l.pinRepeat,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        _Note(_mismatch ? context.l.pinMismatch : ''),
        PinPad(key: _pad, locked: _making, onEntered: _offerPin),
        const SizedBox(height: 26),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 22,
          children: [
            _Link(context.l.commonBack, () => _go(_View.create)),
            _Link(context.l.gateSkip, () => _make(null)),
          ],
        ),
      ],
    );
  }

  static ImageProvider? _fileImage(String? path) =>
      path == null ? null : FileImage(File(path));
}

/// A column in the middle that scrolls when the keyboard or a small screen
/// leaves it no room.
class _Centered extends StatelessWidget {
  const _Centered({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    ),
  );
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: bloomText(
      size: 28,
      weight: 700,
      color: context.bloom.text,
      letterSpacing: -0.4,
    ),
  );
}

/// What went wrong, or nothing; its line is kept so nothing jumps.
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 46,
    child: Center(
      child: SoftText(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.bloom.danger),
      ),
    ),
  );
}

/// A word that acts: muted.
class _Link extends StatelessWidget {
  const _Link(this.text, this.onTap);

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.bloom.text2),
      ),
    ),
  );
}

/// A profile in the list: its face, its name, a lock if it has a PIN.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    required this.onTap,
    required this.face,
    this.locked = false,
  });

  final String label;
  final VoidCallback onTap;
  final Widget face;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final t = context.bloom;
    return Pressable(
      scale: 0.96,
      onTap: onTap,
      child: SizedBox(
        width: 128,
        child: Column(
          children: [
            face,
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: bloomText(size: 15, weight: 600, color: t.text2),
                  ),
                ),
                if (locked) ...[
                  const SizedBox(width: 5),
                  BloomIcon(
                    Bi.lockKeyholeMinimalistic,
                    size: 13,
                    color: t.text2,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
