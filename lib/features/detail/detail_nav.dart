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
/// - из дерева вкладки ближайший навигатор — навигатор ветки, поэтому таб-бар
///   и миниплеер остаются на месте ровно так же, как у вложенных маршрутов.
///   Из плеера ближайший навигатор корневой, и ветку приходится искать самим
///   (см. [_target]).
library;

import 'package:flutter/material.dart';

import '../../app/router.dart';
import '../../core/entities/entities.dart';
import '../../shared/ui/cover_hero.dart';
import '../player/ui/player_sheet.dart';
import 'ui/artist_screen.dart';
import 'ui/set_screen.dart';

/// Навигатор, в который лечь странице, — по контексту того, кто её открыл.
///
/// Обычно это навигатор вкладки, и он же ближайший. Но из полноэкранного плеера
/// (тап по имени артиста, «К артисту» в шторке действий) ближайший навигатор —
/// КОРНЕВОЙ, и страница, положенная в него, накрыла бы таб-бар с миниплеером,
/// хотя из поиска та же страница открывается под ними. Поэтому здесь плеер
/// закрывается — вместе со шторками над ним, как по тапу на пилюлю источника, —
/// а страница уходит в навигатор текущей вкладки.
///
/// Подменяем навигатор, только когда поверх каркаса ЕСТЬ что закрывать и
/// вкладка уже собрана. Иначе корневой навигатор — просто единственный (первый
/// запуск на онбординге, экран из-под теста), и страница идёт в него.
///
/// «Есть что закрывать» — это не только маршруты: плеер лежит слоем поверх
/// каркаса и в стопку навигатора не входит вовсе (см. `PlayerSheet`). Спроси мы
/// об этом один `canPop`, тап по артисту из развёрнутого плеера клал бы
/// страницу в КОРНЕВОЙ навигатор — под всё ещё открытую панель.
NavigatorState _target(BuildContext context) {
  final navigator = Navigator.of(context);
  final root = Navigator.of(context, rootNavigator: true);
  if (navigator != root) return navigator;
  final player = playerSheetOpen.value;
  if (!player && !navigator.canPop()) return navigator;
  final branch = currentBranchNavigator();
  if (branch == null) return navigator;
  navigator.popUntil((r) => r.isFirst);
  collapsePlayerSheet();
  return branch;
}

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
}) =>
    openArtistIn(_target(context), artistId, initial: initial, flight: flight);

/// Страница альбома или плейлиста площадки (не библиотечного — тот открывается
/// маршрутом `/library/list/:id`).
Future<void> openSet(
  BuildContext context,
  Playlist set, {
  CoverFlight? flight,
}) => openSetIn(_target(context), set, flight: flight);

/// То же, но навигатор передан снаружи: пилюля источника открывает страницу из
/// полноэкранного плеера, а он лежит в КОРНЕВОМ навигаторе — своего контекста
/// вкладки у него нет (см. `currentBranchNavigator`).
Future<void> openArtistIn(
  NavigatorState navigator,
  String artistId, {
  Artist? initial,
  CoverFlight? flight,
}) => navigator.push(
  detailPageRoute<void>(
    (_) => ArtistScreen(artistId: artistId, initial: initial, flight: flight),
  ),
);

Future<void> openSetIn(
  NavigatorState navigator,
  Playlist set, {
  CoverFlight? flight,
}) => navigator.push(
  detailPageRoute<void>((_) => SetScreen(set: set, flight: flight)),
);
