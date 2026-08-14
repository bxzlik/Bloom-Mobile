// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get commonBack => 'Назад';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonSave => 'Сохранить';

  @override
  String get commonDelete => 'Удалить';

  @override
  String get commonDone => 'Готово';

  @override
  String get commonApply => 'Применить';

  @override
  String get commonRename => 'Переименовать';

  @override
  String get commonUndo => 'Отменить';

  @override
  String get commonDiscard => 'Отменить';

  @override
  String get commonUpload => 'Загрузить';

  @override
  String get commonPin => 'Закрепить';

  @override
  String get commonUnpin => 'Открепить';

  @override
  String get commonPlay => 'Воспроизвести';

  @override
  String get commonShuffle => 'Перемешать';

  @override
  String get commonFollow => 'Подписаться';

  @override
  String get commonUnfollow => 'Отписаться';

  @override
  String get commonCopyLink => 'Скопировать ссылку';

  @override
  String get commonLinkCopied => 'Ссылка скопирована';

  @override
  String get commonLoadMore => 'Загрузить ещё';

  @override
  String get commonShowMore => 'Показать ещё';

  @override
  String get commonAlbum => 'Альбом';

  @override
  String get commonPlaylist => 'Плейлист';

  @override
  String get commonArtist => 'Артист';

  @override
  String get commonTracks => 'Треки';

  @override
  String get commonPlaylists => 'Плейлисты';

  @override
  String get commonAlbums => 'Альбомы';

  @override
  String get commonArtists => 'Артисты';

  @override
  String get commonAllTracks => 'Все треки';

  @override
  String get commonFavorites => 'Любимые';

  @override
  String get commonHistory => 'История';

  @override
  String get commonLibrary => 'Библиотека';

  @override
  String get commonSort => 'Сортировка';

  @override
  String get commonNewPlaylist => 'Новый плейлист';

  @override
  String get commonCreatePlaylist => 'Создать плейлист';

  @override
  String get commonAddToLibrary => 'В библиотеку';

  @override
  String get commonAlreadyInLibrary => 'Уже в библиотеке';

  @override
  String get commonOfflineBadge => 'офлайн';

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count треков',
      many: '$count треков',
      few: '$count трека',
      one: '$count трек',
    );
    return '$_temp0';
  }

  @override
  String followersCount(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted подписчиков',
      many: '$formatted подписчиков',
      few: '$formatted подписчика',
      one: '$formatted подписчик',
    );
    return '$_temp0';
  }

  @override
  String playsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count раз',
      many: '$count раз',
      few: '$count раза',
      one: '$count раз',
    );
    return '$_temp0';
  }

  @override
  String get navHome => 'Главная';

  @override
  String get navLibrary => 'Библиотека';

  @override
  String get navSettings => 'Настройки';

  @override
  String get sourceLocal => 'Локальные';

  @override
  String get sourceYandex => 'Яндекс.Музыка';

  @override
  String get homeRecent => 'Недавно слушали';

  @override
  String get homeCharts => 'Чарты';

  @override
  String get homeNewReleases => 'Новинки';

  @override
  String get playerPlayingFrom => 'Играет из';

  @override
  String get playerQueue => 'Очередь';

  @override
  String get playerCopied => 'Скопировано';

  @override
  String get playerCopyError => 'Ошибка';

  @override
  String get notifChannelName => 'Воспроизведение';

  @override
  String get notifChannelDescription =>
      'Управление музыкой в шторке и на экране блокировки';

  @override
  String get artistSourceNotConnected => 'Площадка этого артиста не подключена';

  @override
  String get artistNotFound => 'Артист не найден';

  @override
  String get artistPopular => 'Популярные';

  @override
  String get artistReposts => 'Репосты';

  @override
  String get artistSimilar => 'Похожие исполнители';

  @override
  String get artistNoTracks => 'У этого артиста нет доступных треков';

  @override
  String get artistTracksToNewPlaylist => 'Треки в новый плейлист';

  @override
  String get artistNotFoundOnSource => 'Не нашли у площадки';

  @override
  String followedToast(String name) {
    return 'Подписка на $name';
  }

  @override
  String get unfollowedToast => 'Подписка снята';

  @override
  String addedToast(String title, String tracks) {
    return 'Добавлено: $title — $tracks';
  }

  @override
  String get setSourceNotConnected => 'Площадка этого списка не подключена';

  @override
  String get setAlbumNotFound => 'Альбом не найден';

  @override
  String get setPlaylistNotFound => 'Плейлист не найден';

  @override
  String get setNoTracks => 'Нет доступных треков';

  @override
  String get setSaveToLibrary => 'Сохранить в библиотеку';

  @override
  String get libFilterAll => 'Все';

  @override
  String get libEmptyArtists => 'Подписок пока нет';

  @override
  String get libEmptyPlaylists => 'Плейлистов пока нет';

  @override
  String get libEmptyAll => 'Создай плейлист или вставь ссылку в поиск';

  @override
  String get libAutoRefreshTooltip => 'Авто-обновление плейлистов';

  @override
  String get libDragHint => 'В «По умолчанию» плитку можно зажать и перетащить';

  @override
  String get libSortManual => 'По умолчанию';

  @override
  String get libSortNameAsc => 'По имени A–Z';

  @override
  String get libSortNameDesc => 'По имени Z–A';

  @override
  String get libSortType => 'По типу';

  @override
  String get tlSortManual => 'По порядку';

  @override
  String get tlSortName => 'По названию';

  @override
  String get tlSortArtist => 'По исполнителю';

  @override
  String get tlSortDuration => 'По длительности';

  @override
  String get tlNothingFound => 'Ничего не нашлось';

  @override
  String get tlEmptyFav => 'Пока ничего не залайкано';

  @override
  String get tlEmptyHistory => 'История пуста';

  @override
  String get histToday => 'Сегодня';

  @override
  String get histYesterday => 'Вчера';

  @override
  String histDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дней назад',
      many: '$count дней назад',
      few: '$count дня назад',
      one: '$count день назад',
    );
    return '$_temp0';
  }

  @override
  String get histWeekAgo => 'Неделю назад';

  @override
  String get tlEmptyAll => 'В библиотеке пока пусто';

  @override
  String get tlEmptyPlaylist => 'В плейлисте пока пусто';

  @override
  String get tlSearchHint => 'В этом списке';

  @override
  String get tlStopSaving => 'Прервать сохранение';

  @override
  String get tlRemoveOffline => 'Убрать из офлайна';

  @override
  String tlListenOffline(int count) {
    return 'Слушать офлайн ($count)';
  }

  @override
  String tlDownloadFiles(int count) {
    return 'Скачать файлами ($count)';
  }

  @override
  String get tlRefreshTracks => 'Обновить треки';

  @override
  String get tlSetCover => 'Поставить обложку';

  @override
  String get tlChangeCover => 'Сменить обложку';

  @override
  String get tlRemoveCover => 'Убрать обложку';

  @override
  String get tlDeletePlaylist => 'Удалить плейлист';

  @override
  String tlPlaylistDeleted(String name) {
    return 'Плейлист «$name» удалён';
  }

  @override
  String get leAlreadyFavorite => 'Уже в любимых';

  @override
  String leAddedToFavorites(String tracks) {
    return 'В любимые: $tracks';
  }

  @override
  String leDeleteTitle(String tracks) {
    return 'Удалить $tracks?';
  }

  @override
  String get leDeleteBody =>
      'Они пропадут из библиотеки, любимых, плейлистов и истории.';

  @override
  String get leDiscardTitle => 'Отменить правку?';

  @override
  String get leDiscardBody => 'Всё, что вы наменяли в списке, не сохранится.';

  @override
  String cpImported(String title, int count) {
    return 'Импортировано: $title — $count';
  }

  @override
  String get cpAllAlreadyIn => 'Всё это уже в библиотеке';

  @override
  String cpAdded(int count) {
    return 'Добавлено: $count';
  }

  @override
  String get cpSourceNoAnswer => 'Площадка не ответила';

  @override
  String get cpNameHint => 'Мой плейлист';

  @override
  String get cpImportByLink => 'Импортировать по ссылке';

  @override
  String get cpLinkHint => 'Вставьте ссылку…';

  @override
  String cpDestination(String target) {
    return 'Куда: $target';
  }

  @override
  String paEveryMinutes(int count) {
    return '$count мин';
  }

  @override
  String paEveryHours(int count) {
    return '$count ч';
  }

  @override
  String get paJustNow => 'только что';

  @override
  String paMinutesAgo(int count) {
    return '$count мин назад';
  }

  @override
  String paHoursAgo(int count) {
    return '$count ч назад';
  }

  @override
  String paDaysAgo(int count) {
    return '$count дн назад';
  }

  @override
  String get paTitle => 'Авто-обновление';

  @override
  String get paAutoTitle => 'Обновлять автоматически';

  @override
  String get paAutoSubtitle => 'Тянуть новые треки из источников по расписанию';

  @override
  String get paOnStartTitle => 'Проверять при запуске';

  @override
  String get paOnStartSubtitle =>
      'Один проход через несколько секунд после старта';

  @override
  String get paPlaylistsWithSources => 'Плейлисты с источниками';

  @override
  String get paSelectAll => 'Выбрать все';

  @override
  String get paDeselectAll => 'Снять все';

  @override
  String get paNothingToRefresh =>
      'Обновлять нечего: ни один плейлист не импортирован по ссылке. Вставьте ссылку в поле поиска — импортированный плейлист запомнит источник.';

  @override
  String get paRefreshing => 'Идёт обновление…';

  @override
  String get paNeverRefreshed => 'Ещё не обновлялось';

  @override
  String paLastRun(String ago) {
    return 'Последний проход: $ago';
  }

  @override
  String get paSoon => 'вот-вот';

  @override
  String paNextIn(String time) {
    return 'через $time';
  }

  @override
  String paSelected(int selected, int total) {
    return 'Выбрано: $selected из $total';
  }

  @override
  String get paPeriod => 'Периодичность';

  @override
  String get paRunUpdating => 'обновляем…';

  @override
  String get paRunError => 'ошибка';

  @override
  String get paRunNoChanges => 'без изменений';

  @override
  String get paRefreshNow => 'Обновить сейчас';

  @override
  String paBusy(int count) {
    return 'Обновляю $count…';
  }

  @override
  String paProgress(int done, int total) {
    return 'Обновляю: $done/$total';
  }

  @override
  String paNewTracks(int added, int playlists) {
    return 'Новых треков: $added (плейлистов: $playlists)';
  }

  @override
  String paFailed(int count) {
    return 'Не удалось обновить плейлистов: $count';
  }

  @override
  String get paNoNewTracks => 'Новых треков нет';

  @override
  String rpBusy(String name) {
    return 'Обновляю «$name»…';
  }

  @override
  String get rpNoAnswer => 'Источник не ответил';

  @override
  String rpNewTracks(int count) {
    return 'Новых треков: $count';
  }

  @override
  String get iuUnrecognized => 'Не удалось распознать ссылку';

  @override
  String iuLikesTitle(String name) {
    return 'Лайки · $name';
  }

  @override
  String get iuOnlySupported =>
      'Можно вставить только плейлист, альбом или лайки';

  @override
  String get iuNoTracks => 'В этой ссылке нет треков';

  @override
  String get iuPlaylistGone => 'Плейлист больше не существует';

  @override
  String get ofRemoved => 'Убрано из офлайна';

  @override
  String get ofSaving => 'Сохранение для офлайна…';

  @override
  String ofAvailable(String name) {
    return 'Доступно офлайн: $name';
  }

  @override
  String get ofNothingToSave => 'Здесь нечего сохранять офлайн';

  @override
  String get ofDownloadingTrack => 'Скачиваю трек…';

  @override
  String ofSaved(String path) {
    return 'Сохранено: $path';
  }

  @override
  String get ofDownloadingFiles => 'Скачиваю файлами…';

  @override
  String get ofNothingToDownload => 'Здесь нечего скачивать';

  @override
  String get ofNoCopies => 'Офлайн-копий не было';

  @override
  String ofRemovedCount(int count) {
    return 'Убрано из офлайна: $count';
  }

  @override
  String ofSavingProgress(int done, int total) {
    return 'Сохраняю: $done/$total';
  }

  @override
  String get ofAbort => 'Прервать';

  @override
  String get ofNoStorage => 'Нет доступа к хранилищу';

  @override
  String get ofCantSaveTrack => 'Этот трек нельзя сохранить офлайн';

  @override
  String get ofBusyWithAnother => 'Уже качаю другой список';

  @override
  String ofDownloadedAll(int count) {
    return 'Скачано треков: $count';
  }

  @override
  String get ofDownloadedNone => 'Не удалось скачать ни одного трека';

  @override
  String ofDownloadedPartial(int ok, int total, int failed) {
    return 'Скачано $ok из $total, не вышло: $failed';
  }

  @override
  String get ofStreamOnly =>
      'Этот трек отдаётся только потоком — сохранить нельзя';

  @override
  String get ofDrm => 'Трек защищён DRM';

  @override
  String get ofNoFileLink => 'Площадка не отдала ссылку на файл';

  @override
  String get ofNoConnection => 'Нет соединения';

  @override
  String ofSaveFailed(String message) {
    return 'Не удалось сохранить: $message';
  }

  @override
  String get fdPathIos => 'Файлы → На iPhone → Bloom';

  @override
  String get fdPathAndroid => 'Музыка/Bloom';

  @override
  String get fdCantDownload => 'Этот трек нельзя скачать';

  @override
  String get fdNeedPermission =>
      'Нужен доступ к памяти телефона — разрешите и повторите';

  @override
  String get fdSaveFailed => 'Не удалось сохранить файл';

  @override
  String get fdDownloadFile => 'Скачать файлом';

  @override
  String get taRemoveFromFavorites => 'Убрать из любимых';

  @override
  String get taAddToFavorites => 'В любимые';

  @override
  String get taAddToPlaylist => 'Добавить в плейлист';

  @override
  String get taListenOffline => 'Слушать офлайн';

  @override
  String get taRemoveOffline => 'Убрать из офлайна';

  @override
  String get taGoToArtist => 'Перейти к артисту';

  @override
  String get taDeleteTrack => 'Удалить трек';

  @override
  String get taTrackDeleted => 'Трек удалён';

  @override
  String get taAddedToLibrary => 'Добавлено в библиотеку';

  @override
  String get searchTabAll => 'Всё';

  @override
  String get searchHint => 'Поиск';

  @override
  String get searchSource => 'Источник';

  @override
  String get searchSourceAll => 'Все источники';

  @override
  String get searchNothingFound => 'Ничего не нашлось';

  @override
  String get searchFindSomething => 'Найди что-нибудь';

  @override
  String get searchSectionEmpty => 'В этом разделе ничего не нашлось';

  @override
  String pvLikesOf(String name) {
    return 'Лайки $name';
  }

  @override
  String pvPlaylistCreated(String tracks) {
    return 'Плейлист создан — $tracks';
  }

  @override
  String pvImporting(int count) {
    return 'Импортирую $count…';
  }

  @override
  String pvImportProgress(int done, int total) {
    return 'Импортирую: $done/$total';
  }

  @override
  String pvImported(int ok, int total) {
    return 'Импортировано: $ok из $total';
  }

  @override
  String pvPlaylistsTitle(int count) {
    return 'Плейлисты · $count';
  }

  @override
  String get pvImportAll => 'Импортировать все';

  @override
  String pvLikesTitle(int count) {
    return 'Лайки · $count';
  }

  @override
  String get pvToPlaylist => 'В плейлист';

  @override
  String get pvNothingPublic =>
      'У этого аккаунта нет открытых плейлистов и лайков';

  @override
  String pvAdded(String tracks) {
    return 'Добавлено: $tracks';
  }

  @override
  String get profileDefaultName => 'Пользователь';

  @override
  String get profileNickCopied => 'Ник скопирован!';

  @override
  String get profileStats => 'Статистика';

  @override
  String get profileAchievements => 'Достижения';

  @override
  String get profileNowPlaying => 'Слушает сейчас: ';

  @override
  String get profileSaved => 'Профиль сохранён!';

  @override
  String get profileNickname => 'НИКНЕЙМ';

  @override
  String get profileNicknameHint => 'Введи никнейм...';

  @override
  String get profileAbout => 'О СЕБЕ';

  @override
  String get profileAboutHint => 'Расскажи о себе...';

  @override
  String get profileStatus => 'СТАТУС';

  @override
  String get profileStatusHint => '\"Мой статус...\"';

  @override
  String get profileDisc => 'ПЛАСТИНКА';

  @override
  String get profileColorSolid => 'Цвет';

  @override
  String get profileColorGradient => 'Градиент';

  @override
  String get profileRemoveImage => 'Убрать картинку';

  @override
  String get profileRemovePhoto => 'Убрать фото';

  @override
  String profileZoom(int percent) {
    return 'Масштаб  $percent%';
  }

  @override
  String achUnlockedToast(String name, String tier) {
    return '🏅 Достижение получено: $name — $tier';
  }

  @override
  String get achMax => 'Максимум';

  @override
  String achUnlockedAt(String date) {
    return 'получено $date';
  }

  @override
  String get achTierBronze => 'Бронза';

  @override
  String get achTierSilver => 'Серебро';

  @override
  String get achTierGold => 'Золото';

  @override
  String get achListenerName => 'Меломан';

  @override
  String get achListenerDesc => 'Всего прослушиваний';

  @override
  String get achTimeName => 'В наушниках';

  @override
  String get achTimeDesc => 'Время прослушивания';

  @override
  String get achStreakName => 'На волне';

  @override
  String get achStreakDesc => 'Дней подряд с прослушиваниями';

  @override
  String get achMarathonName => 'Марафонец';

  @override
  String get achMarathonDesc => 'Треков за один день';

  @override
  String get achVeteranName => 'Ветеран Bloom';

  @override
  String get achVeteranDesc => 'Время в приложении';

  @override
  String get achDevoteeName => 'Преданность';

  @override
  String get achDevoteeDesc => 'Активных дней всего';

  @override
  String get statsTracks => 'Треков';

  @override
  String get statsPlays => 'Прослушано';

  @override
  String get statsTime => 'Время прослушивания';

  @override
  String get statsUnique => 'Уникальных';

  @override
  String get statsAvgLength => 'Средняя длина';

  @override
  String get statsFavArtist => 'Любимый исполнитель';

  @override
  String get statsAppTime => 'Время в приложении';

  @override
  String get statsRecordDay => 'Рекорд дня';

  @override
  String get statsAvgPerDay => 'В среднем за день';

  @override
  String get statsHoursDay => 'часов/день';

  @override
  String get statsTracksDay => 'треков/день';

  @override
  String get statsArtists => 'артистов';

  @override
  String get statsSources => 'Где слушали чаще';

  @override
  String get statsTopTracks => 'Топ треков';

  @override
  String get statsActivity => 'Активность';

  @override
  String get statsTopArtists => 'Топ исполнителей';

  @override
  String get statsLocalFiles => 'Локальные файлы';

  @override
  String get statsNoDataYet => 'Пока нет данных';

  @override
  String get statsFootnote =>
      'Считается по истории прослушиваний на этом устройстве';

  @override
  String get statsCopy => 'Скопировать';

  @override
  String get statsClear => 'Очистить';

  @override
  String get statsClearConfirm => 'Точно? Ещё раз';

  @override
  String get statsCopied => 'Статистика скопирована';

  @override
  String get statsCleared => 'Статистика очищена';

  @override
  String get statsToday => 'сег.';

  @override
  String get statsPeriod7d => '7д';

  @override
  String get statsPeriod30d => '30д';

  @override
  String get statsPeriodAll => 'Всё';

  @override
  String get statsLess => 'меньше';

  @override
  String get statsMore => 'больше';

  @override
  String get statsZeroMinutes => '0 мин';

  @override
  String statsHoursMinutes(int hours, int minutes) {
    return '$hoursч $minutesм';
  }

  @override
  String statsMinutes(int minutes) {
    return '$minutes мин';
  }

  @override
  String get statsShareTitle => '🎵 Моя статистика в Bloom';

  @override
  String statsShareTracks(int count) {
    return '📚 Треков: $count';
  }

  @override
  String statsShareUnique(int count) {
    return '🎵 Уникальных: $count';
  }

  @override
  String statsSharePlays(int count) {
    return '▶️ Прослушано: $count';
  }

  @override
  String statsShareTime(String value) {
    return '🎧 Время прослушивания: $value';
  }

  @override
  String statsShareAvgLength(String value) {
    return '📏 Средняя длина: $value';
  }

  @override
  String statsShareAppTime(String value) {
    return '⏱️ Время в приложении: $value';
  }

  @override
  String statsShareFavArtist(String name) {
    return '⭐ Любимый исполнитель: $name';
  }

  @override
  String statsShareRecordDay(int count) {
    return '🏆 Рекорд дня: $count';
  }

  @override
  String get statsShareAvgPerDay => '📈 В среднем за день:';

  @override
  String get statsShareSources => '📡 Где слушали чаще:';

  @override
  String get statsShareTopTracks => '🔥 Топ треков:';

  @override
  String get statsShareTopArtists => '👤 Топ исполнителей:';

  @override
  String get setGroupMain => 'ОСНОВНОЕ';

  @override
  String get setGroupAppearance => 'ОФОРМЛЕНИЕ';

  @override
  String get setGroupIntegrations => 'ИНТЕГРАЦИИ';

  @override
  String get setSystem => 'Система';

  @override
  String get setAudio => 'Аудио';

  @override
  String get setSwipes => 'Свайпы';

  @override
  String get setStorage => 'Хранилище';

  @override
  String get setPlayer => 'Плеер';

  @override
  String get setInterface => 'Интерфейс';

  @override
  String get setCustomization => 'Кастомизация';

  @override
  String setStub(String title) {
    return '«$title» ещё не сделан';
  }

  @override
  String get swZoneLibrary => 'Библиотека';

  @override
  String get swZoneQueue => 'Очередь';

  @override
  String get swZoneMini => 'Мини-плеер';

  @override
  String get swZonePlayer => 'Плеер';

  @override
  String get swLeft => 'Свайп влево';

  @override
  String get swRight => 'Свайп вправо';

  @override
  String get swActNone => 'Отключено';

  @override
  String get swActLike => 'Лайк';

  @override
  String get swActQueue => 'Добавить в очередь';

  @override
  String get swActPlayNext => 'Следующим';

  @override
  String get swActNext => 'Следующий';

  @override
  String get swActPrev => 'Предыдущий';

  @override
  String get swActDownload => 'Скачать';

  @override
  String get swActDelete => 'Удалить';

  @override
  String get swAddedToQueue => 'Добавлено в очередь';

  @override
  String get swAlreadyInQueue => 'Уже в очереди';

  @override
  String get swPlaysNext => 'Заиграет следующим';

  @override
  String get swLiked => 'Добавлено в любимые';

  @override
  String get swUnliked => 'Убрано из любимых';

  @override
  String get swRemoved => 'Убрано';

  @override
  String get apLanguage => 'ЯЗЫК';

  @override
  String get apLanguageRu => 'Русский';

  @override
  String get apLanguageEn => 'English';

  @override
  String get apTheme => 'ТЕМА';

  @override
  String get apThemeRow => 'Тема';

  @override
  String get thNew => 'Своя тема';

  @override
  String get thNameDefault => 'Моя тема';

  @override
  String get thSlotBg => 'Фон';

  @override
  String get thSlotCard => 'Карточка';

  @override
  String get thSlotAccent => 'Акцент';

  @override
  String get thRandom => 'Случайные цвета';

  @override
  String thCreated(String name) {
    return 'Тема «$name» создана';
  }

  @override
  String get thDeleted => 'Пресет удалён';

  @override
  String get apAutoAccent => 'Авто акцент';

  @override
  String get apAutoAccentSub => 'Цвет акцента из обложки трека';

  @override
  String get apAutoAccentLevel => 'Яркость акцента';

  @override
  String get apCorners => 'СКРУГЛЕНИЯ';

  @override
  String get apPreviewTitle => 'Так выглядит блок';

  @override
  String get apPreviewSubtitle => 'и второстепенный текст';

  @override
  String get apBadgesTitle => 'Бейджи в цвете акцента';

  @override
  String get apBadgesSubtitle =>
      'По умолчанию бейджи источников в своих фирменных цветах; включи — красить в акцент';

  @override
  String get scHelp =>
      'Обычно не нужен: ключ подбирается сам — скрейпом сайта, а если не вышло, перебором известных. Своё значение имеет смысл вбить, если SoundCloud перестал отвечать.';

  @override
  String get scHint => 'Автоматически';

  @override
  String get scCheckConnection => 'Проверить соединение';

  @override
  String get scConnectionOk => 'Соединение работает';

  @override
  String get scConnectionFail => 'Не отвечает';

  @override
  String get scActiveKey => 'Активный ключ';

  @override
  String get ymChecking => 'Проверяю…';

  @override
  String get ymConnected => '✓ Подключено';

  @override
  String get ymNotConnected => 'Не подключено';

  @override
  String get ymLogout => 'Выйти';

  @override
  String get ymPlusActiveA => 'Яндекс Плюс активен';

  @override
  String get ymPlusActiveB => '— треки играют напрямую из Яндекса.';

  @override
  String get ymPlusNoneA => 'Без Плюса';

  @override
  String get ymPlusNoneB =>
      '— некоторые треки могут быть недоступны для воспроизведения.';

  @override
  String get ymPlusUnknown => 'Статус подписки неизвестен.';

  @override
  String get ymLoginHint =>
      'Войди через Яндекс ID. Откроется страница подтверждения — введи там код.';

  @override
  String get ymConnect => 'Подключить Яндекс.Музыку';

  @override
  String get ymCodePromptA => 'Открой';

  @override
  String get ymCodePromptB => 'и введи код:';

  @override
  String get ymOpenPage => 'Открыть страницу';

  @override
  String get ymCodeCopied => 'Код скопирован';

  @override
  String get ymGettingCode => 'Получаю код…';

  @override
  String get ymWaiting => 'Ожидаю подтверждения…';

  @override
  String get ymCodeExpired => 'Код истёк — нажми «Подключить» заново.';

  @override
  String get ymErrAuth =>
      'Токен Яндекс.Музыки недействителен — авторизуйся заново';

  @override
  String get ymErrNeedPlus => 'Трек недоступен — нужна подписка Яндекс Плюс';

  @override
  String get ymErrNetwork => 'Яндекс не отвечает';

  @override
  String get ytmConfigured => 'Настроен';

  @override
  String get ytmNoAuth => 'Пока что, авторизация не нужна';

  @override
  String get ytmHelp =>
      'Поиск, страницы и импорт по ссылке работают без авторизации. Воспроизведение и скачивание идут напрямую с YouTube.';

  @override
  String get stOfflineCache => 'Офлайн-кеш треков';

  @override
  String get stCounting => 'Считаю…';

  @override
  String stCacheStats(int count, String size) {
    return '$count треков · $size';
  }

  @override
  String get stHelp =>
      'Скачанные треки играют без сети и не тратят трафик. Лежат внутри приложения — другим плеерам не видны и удаляются вместе с Bloom.';

  @override
  String get stClear => 'Очистить офлайн-кеш';

  @override
  String get stClearTitle => 'Очистить офлайн-кеш?';

  @override
  String get stClearBody =>
      'Скачанные копии будут удалены, и эти треки перестанут играть без сети. Из библиотеки и плейлистов они никуда не денутся.';

  @override
  String stCleared(int count) {
    return 'Офлайн-кеш очищен, удалено файлов: $count';
  }

  @override
  String stBytes(String value) {
    return '$value Б';
  }

  @override
  String stKilobytes(String value) {
    return '$value КБ';
  }

  @override
  String stMegabytes(String value) {
    return '$value МБ';
  }

  @override
  String stGigabytes(String value) {
    return '$value ГБ';
  }
}
