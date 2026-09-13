/// Аватарки артистов трека — стопкой перед их именем в плеере.
///
/// Настоящие аватарки с площадки, те же самые, что показывает шторка выбора
/// артистов: у трека своя картинка есть только у аккаунта, который его залил,
/// остальных приходится искать по имени ([findArtistCached]). Поиск общий со
/// шторкой, поэтому открытая до этого шторка (и наоборот) уже всё нашла.
///
/// Пока ищем и грузим — не показываем НИЧЕГО, не нашли или картинка битая —
/// тоже: заглушка со знаком bloom рядом с именем читалась бы как чужая
/// аватарка, а пустой кружок — как недогруз. Строка с именем от этого
/// разъезжается один раз, когда картинки приезжают.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/entities/entities.dart';
import '../../../core/providers/artist_lookup.dart';
import '../../../core/providers/music_provider.dart';
import '../../../core/store/cover_store.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/atoms.dart';
import '../../../shared/util/artists.dart';

/// Диаметр кружка. Подпись в плеере 16 px — аватарка чуть выше строчных букв,
/// чтобы читаться картинкой, но не спорить с именем.
const double _size = 22;

/// На сколько следующий кружок заезжает под предыдущий.
const double _overlap = 9;

/// Просвет между соседними кружками. Не обводка, а ВЫРЕЗ: под плеером стоит
/// размытая обложка, и любая сплошная рамка была бы на ней пятном.
const double _gap = 2;

/// Отступ от стопки до имени.
const double _lead = 8;

/// «Неизвестный исполнитель» на всех языках — не имя, искать его по площадкам
/// бессмысленно. Все языки, а не текущий: строка пишется в трек при импорте
/// локального файла и остаётся на языке, который был тогда.
final Set<String> _unknownArtist = {
  for (final locale in AppLocalizations.supportedLocales)
    lookupAppLocalizations(locale).commonUnknownArtist,
};

class TrackArtistAvatars extends ConsumerStatefulWidget {
  const TrackArtistAvatars({super.key, required this.track});

  final Track track;

  @override
  ConsumerState<TrackArtistAvatars> createState() => _TrackArtistAvatarsState();
}

class _TrackArtistAvatarsState extends ConsumerState<TrackArtistAvatars> {
  /// Имена в порядке строки трека. Заодно метка «того самого» запроса: список
  /// пересоздаётся на каждой смене трека, и по нему поиск понимает, что искал
  /// для уже уехавшего трека.
  List<String> _names = const [];

  /// Имя → ссылка на аватарку. Чего в карте нет — либо ещё ищем, либо не нашли;
  /// показываем мы в обоих случаях одинаково (никак), различать незачем.
  Map<String, String> _urls = {};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(TrackArtistAvatars old) {
    super.didUpdateWidget(old);
    // Тот же трек с той же строкой артистов — уже найденное на месте, заново
    // ходить в сеть незачем.
    if (old.track.id == widget.track.id &&
        old.track.artist == widget.track.artist) {
      return;
    }
    _sync();
  }

  void _sync() {
    // Кружок на КАЖДОЕ имя, без потолка, как на десктопе: обрезанная на трёх
    // стопка врала, что артистов трое.
    final artist = widget.track.artist.trim();
    final names = _unknownArtist.contains(artist)
        ? const <String>[]
        : parseArtists(artist);
    _names = names;
    _urls = {};

    // Артист один — значит строка трека и есть имя аккаунта, который его залил,
    // а его аватарку трек уже везёт с собой — искать не надо, только догрузить.
    final own = widget.track.artistAvatar;
    if (names.length == 1 && own != null && own.isNotEmpty) {
      unawaited(_accept(names, names.first, own));
      return;
    }
    if (names.isEmpty) return;
    unawaited(_resolve(names));
  }

  /// Ставит картинку в стопку, только когда она ДОГРУЗИЛАСЬ. Битая ссылка
  /// выпадает из стопки целиком, как на десктопе: заглушка [Cover] на её месте
  /// читалась бы чужой аватаркой, и пока грузится — тоже.
  Future<void> _accept(List<String> forNames, String name, String url) async {
    if (!await _loads(url)) return;
    // Трек мог смениться, пока грузили: тогда ответ уже не про то, что на
    // экране.
    if (!mounted || !identical(_names, forNames)) return;
    setState(() => _urls[name] = url);
  }

  Future<void> _resolve(List<String> names) async {
    final provider = ref.read(registryProvider).byId(widget.track.source.id);
    // Площадки нет (трек из библиотеки, провайдер выключен) — искать негде:
    // у имени просто не будет картинки.
    if (provider == null) return;
    // Одинаковые имена в строке («A & A») ищем один раз.
    await Future.wait([
      for (final name in names.toSet()) _one(provider, names, name),
    ]);
  }

  Future<void> _one(
    MusicProvider provider,
    List<String> forNames,
    String name,
  ) async {
    String? url;
    try {
      url = (await findArtistCached(provider, name))?.avatar;
    } catch (_) {
      // Сети нет или площадка отказала — имя останется без картинки.
    }
    if (!mounted || !identical(_names, forNames)) return;
    if (url == null || url.isEmpty) return;
    await _accept(forNames, name, url);
  }

  @override
  Widget build(BuildContext context) {
    final urls = [
      for (final name in _names)
        if (_urls[name] != null) _urls[name]!,
    ];
    if (urls.isEmpty) return const SizedBox.shrink();

    final step = _size - _overlap;
    return Padding(
      padding: const EdgeInsets.only(right: _lead),
      child: SizedBox(
        width: _size + step * (urls.length - 1),
        height: _size,
        child: Stack(
          children: [
            // Рисуем с хвоста: первый артист остаётся ПОВЕРХ остальных — он же
            // первым стоит и в имени.
            for (final i in List.generate(urls.length, (i) => i).reversed)
              Positioned(
                left: step * i,
                child: ClipPath(
                  // Кружок под соседом слева выгрызает у себя его край с
                  // просветом — так стопка читается на любом фоне.
                  clipper: i == 0
                      ? null
                      : _NeighbourBite(step: step, gap: _gap),
                  child: Cover(url: urls[i], size: _size, circle: true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `true` — картинка декодировалась (и лежит в кеше, так что [Cover] покажет её
/// сразу), `false` — ссылка битая или сети нет.
Future<bool> _loads(String url) {
  final image = coverImage(url);
  if (image == null) return Future.value(false);
  final done = Completer<bool>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish(bool ok) {
    if (!done.isCompleted) done.complete(ok);
    stream.removeListener(listener);
  }

  listener = ImageStreamListener(
    (_, _) => finish(true),
    onError: (_, _) => finish(false),
  );
  stream.addListener(listener);
  return done.future;
}

/// Круг за вычетом соседа слева, раздутого на [gap].
class _NeighbourBite extends CustomClipper<Path> {
  const _NeighbourBite({required this.step, required this.gap});

  /// Насколько левее стоит центр соседа.
  final double step;
  final double gap;

  @override
  Path getClip(Size size) {
    final self = Path()..addOval(Offset.zero & size);
    final hole = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width / 2 - step, size.height / 2),
          radius: size.width / 2 + gap,
        ),
      );
    return Path.combine(PathOperation.difference, self, hole);
  }

  @override
  bool shouldReclip(_NeighbourBite old) => old.step != step || old.gap != gap;
}
