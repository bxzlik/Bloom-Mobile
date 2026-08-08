/// Переходы на страницы артиста и альбома/плейлиста.
///
/// Обе входят растворением на месте ([detailPageRoute]), а не общим переходом
/// со сдвигом: в шапку каждой из них летит обложка с карточки, и сдвиг всей
/// страницы спорил бы с этим перелётом.
///
/// Push обычным навигатором, а не маршрутом `go_router`. Причины две:
/// - страницы рекурсивны (артист → альбом → артист → …), а именованный
///   маршрут пришлось бы заводить в КАЖДОЙ ветке `StatefulShellRoute` и
///   `context.push('/home/...')` из библиотеки перекидывал бы на чужой таб;
/// - ближайший навигатор здесь — навигатор ветки, поэтому таб-бар и миниплеер
///   остаются на месте ровно так же, как у вложенных маршрутов.
library;

import 'package:flutter/material.dart';

import '../../core/entities/entities.dart';
import '../../shared/ui/cover_hero.dart';
import 'ui/artist_screen.dart';
import 'ui/set_screen.dart';

/// Страница артиста. [initial] — то, с чем открыли (карточка поиска, подписка):
/// шапка рисуется сразу, не дожидаясь сети.
///
/// [flight] — аватарка карточки, с которой уходим: она перелетит в шапку.
/// Без неё страница просто проявляется.
Future<void> openArtist(
  BuildContext context,
  String artistId, {
  Artist? initial,
  CoverFlight? flight,
}) => Navigator.of(context).push(
  detailPageRoute<void>(
    (_) => ArtistScreen(artistId: artistId, initial: initial, flight: flight),
  ),
);

/// Страница альбома или плейлиста площадки (не библиотечного — тот открывается
/// маршрутом `/library/list/:id`).
Future<void> openSet(
  BuildContext context,
  Playlist set, {
  CoverFlight? flight,
}) => Navigator.of(
  context,
).push(detailPageRoute<void>((_) => SetScreen(set: set, flight: flight)));
