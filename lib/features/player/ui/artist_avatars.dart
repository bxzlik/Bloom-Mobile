/// Аватарки артистов трека — стопкой перед их именем в плеере.
///
/// Настоящие аватарки с площадки, те же самые, что показывает шторка выбора
/// артистов: у трека своя картинка есть только у аккаунта, который его залил,
/// остальных приходится искать по имени ([findArtistCached]). Поиск общий со
/// шторкой, поэтому открытая до этого шторка (и наоборот) уже всё нашла.
///
/// Пока ищем — не показываем НИЧЕГО, и не нашли — тоже: заглушка со знаком
/// bloom рядом с именем читалась бы как чужая аватарка, а пустой кружок — как
/// недогруз. Строка с именем от этого разъезжается один раз, когда картинки
/// приезжают; у трека с одним артистом этого не видно вовсе — его аватарка
/// приходит вместе с треком, без сети.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/entities/entities.dart';
import '../../../core/providers/artist_lookup.dart';
import '../../../core/providers/music_provider.dart';
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

/// Сколько кружков показываем. Строка «A, B, C, D, E» дала бы стопку шире
/// самого имени; хвост просто не рисуем — все артисты и так перечислены рядом
/// текстом.
const int _max = 3;

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
    final names = parseArtists(widget.track.artist).take(_max).toList();
    _names = names;
    _urls = {};

    // Артист один — значит строка трека и есть имя аккаунта, который его залил,
    // а его аватарку трек уже везёт с собой. Это обычный случай, и он обходится
    // без сети и без разъезжающейся строки.
    final own = widget.track.artistAvatar;
    if (names.length == 1 && own != null && own.isNotEmpty) {
      _urls[names.first] = own;
      return;
    }
    if (names.isEmpty) return;
    unawaited(_resolve(names));
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
    // Трек мог смениться, пока искали: тогда ответ уже не про то, что на
    // экране.
    if (!mounted || !identical(_names, forNames)) return;
    if (url == null || url.isEmpty) return;
    setState(() => _urls[name] = url!);
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
