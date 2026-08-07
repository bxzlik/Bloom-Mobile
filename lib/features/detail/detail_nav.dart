/// Переходы на страницы артиста и альбома/плейлиста.
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
import 'ui/artist_screen.dart';
import 'ui/set_screen.dart';

/// Страница артиста. [initial] — то, с чем открыли (карточка поиска, подписка):
/// шапка рисуется сразу, не дожидаясь сети.
Future<void> openArtist(
  BuildContext context,
  String artistId, {
  Artist? initial,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => ArtistScreen(artistId: artistId, initial: initial),
  ),
);

/// Страница альбома или плейлиста площадки (не библиотечного — тот открывается
/// маршрутом `/library/list/:id`).
Future<void> openSet(BuildContext context, Playlist set) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => SetScreen(set: set)));
