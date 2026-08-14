// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonBack => 'Back';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonDone => 'Done';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonDiscard => 'Discard';

  @override
  String get commonUpload => 'Upload';

  @override
  String get commonPin => 'Pin';

  @override
  String get commonUnpin => 'Unpin';

  @override
  String get commonPlay => 'Play';

  @override
  String get commonShuffle => 'Shuffle';

  @override
  String get commonFollow => 'Follow';

  @override
  String get commonUnfollow => 'Unfollow';

  @override
  String get commonCopyLink => 'Copy link';

  @override
  String get commonLinkCopied => 'Link copied';

  @override
  String get commonLoadMore => 'Load more';

  @override
  String get commonShowMore => 'Show more';

  @override
  String get commonAlbum => 'Album';

  @override
  String get commonPlaylist => 'Playlist';

  @override
  String get commonArtist => 'Artist';

  @override
  String get commonTracks => 'Tracks';

  @override
  String get commonPlaylists => 'Playlists';

  @override
  String get commonAlbums => 'Albums';

  @override
  String get commonArtists => 'Artists';

  @override
  String get commonAllTracks => 'All tracks';

  @override
  String get commonFavorites => 'Liked';

  @override
  String get commonHistory => 'History';

  @override
  String get commonLibrary => 'Library';

  @override
  String get commonSort => 'Sort';

  @override
  String get commonNewPlaylist => 'New playlist';

  @override
  String get commonCreatePlaylist => 'Create playlist';

  @override
  String get commonAddToLibrary => 'Add to library';

  @override
  String get commonAlreadyInLibrary => 'Already in your library';

  @override
  String get commonOfflineBadge => 'offline';

  @override
  String tracksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks',
      one: '$count track',
    );
    return '$_temp0';
  }

  @override
  String followersCount(int count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted followers',
      one: '$formatted follower',
    );
    return '$_temp0';
  }

  @override
  String playsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plays',
      one: '$count play',
    );
    return '$_temp0';
  }

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Library';

  @override
  String get navSettings => 'Settings';

  @override
  String get sourceLocal => 'Local';

  @override
  String get sourceYandex => 'Yandex Music';

  @override
  String get homeRecent => 'Recently played';

  @override
  String get homeCharts => 'Charts';

  @override
  String get homeNewReleases => 'New releases';

  @override
  String get playerPlayingFrom => 'Playing from';

  @override
  String get playerQueue => 'Queue';

  @override
  String get playerCopied => 'Copied';

  @override
  String get playerCopyError => 'Error';

  @override
  String get notifChannelName => 'Playback';

  @override
  String get notifChannelDescription =>
      'Music controls in the notification shade and on the lock screen';

  @override
  String get artistSourceNotConnected => 'This artist’s source isn’t connected';

  @override
  String get artistNotFound => 'Artist not found';

  @override
  String get artistPopular => 'Popular';

  @override
  String get artistReposts => 'Reposts';

  @override
  String get artistSimilar => 'Fans might also like';

  @override
  String get artistNoTracks => 'This artist has no available tracks';

  @override
  String get artistTracksToNewPlaylist => 'Tracks to a new playlist';

  @override
  String get artistNotFoundOnSource => 'Not found on the source';

  @override
  String followedToast(String name) {
    return 'Following $name';
  }

  @override
  String get unfollowedToast => 'Unfollowed';

  @override
  String addedToast(String title, String tracks) {
    return 'Added: $title — $tracks';
  }

  @override
  String get setSourceNotConnected => 'This list’s source isn’t connected';

  @override
  String get setAlbumNotFound => 'Album not found';

  @override
  String get setPlaylistNotFound => 'Playlist not found';

  @override
  String get setNoTracks => 'No tracks available';

  @override
  String get setSaveToLibrary => 'Save to library';

  @override
  String get libFilterAll => 'All';

  @override
  String get libEmptyArtists => 'No subscriptions yet';

  @override
  String get libEmptyPlaylists => 'No playlists yet';

  @override
  String get libEmptyAll => 'Create a playlist or paste a link into search';

  @override
  String get libAutoRefreshTooltip => 'Playlist auto-refresh';

  @override
  String get libDragHint => 'In “Default” order a tile can be held and dragged';

  @override
  String get libSortManual => 'Default';

  @override
  String get libSortNameAsc => 'By name A–Z';

  @override
  String get libSortNameDesc => 'By name Z–A';

  @override
  String get libSortType => 'By type';

  @override
  String get tlSortManual => 'In order';

  @override
  String get tlSortName => 'By title';

  @override
  String get tlSortArtist => 'By artist';

  @override
  String get tlSortDuration => 'By length';

  @override
  String get tlNothingFound => 'Nothing found';

  @override
  String get tlEmptyFav => 'Nothing liked yet';

  @override
  String get tlEmptyHistory => 'History is empty';

  @override
  String get histToday => 'Today';

  @override
  String get histYesterday => 'Yesterday';

  @override
  String histDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '$count day ago',
    );
    return '$_temp0';
  }

  @override
  String get histWeekAgo => 'A week ago';

  @override
  String get tlEmptyAll => 'Your library is empty';

  @override
  String get tlEmptyPlaylist => 'This playlist is empty';

  @override
  String get tlSearchHint => 'In this list';

  @override
  String get tlStopSaving => 'Stop saving';

  @override
  String get tlRemoveOffline => 'Remove from offline';

  @override
  String tlListenOffline(int count) {
    return 'Listen offline ($count)';
  }

  @override
  String tlDownloadFiles(int count) {
    return 'Download as files ($count)';
  }

  @override
  String get tlRefreshTracks => 'Refresh tracks';

  @override
  String get tlSetCover => 'Set a cover';

  @override
  String get tlChangeCover => 'Change cover';

  @override
  String get tlRemoveCover => 'Remove cover';

  @override
  String get tlDeletePlaylist => 'Delete playlist';

  @override
  String tlPlaylistDeleted(String name) {
    return 'Playlist “$name” deleted';
  }

  @override
  String get leAlreadyFavorite => 'Already liked';

  @override
  String leAddedToFavorites(String tracks) {
    return 'Liked: $tracks';
  }

  @override
  String leDeleteTitle(String tracks) {
    return 'Delete $tracks?';
  }

  @override
  String get leDeleteBody =>
      'They will disappear from your library, likes, playlists and history.';

  @override
  String get leDiscardTitle => 'Discard changes?';

  @override
  String get leDiscardBody =>
      'Everything you changed in this list will be lost.';

  @override
  String cpImported(String title, int count) {
    return 'Imported: $title — $count';
  }

  @override
  String get cpAllAlreadyIn => 'All of it is already in your library';

  @override
  String cpAdded(int count) {
    return 'Added: $count';
  }

  @override
  String get cpSourceNoAnswer => 'The source didn’t respond';

  @override
  String get cpNameHint => 'My playlist';

  @override
  String get cpImportByLink => 'Import from a link';

  @override
  String get cpLinkHint => 'Paste a link…';

  @override
  String cpDestination(String target) {
    return 'To: $target';
  }

  @override
  String paEveryMinutes(int count) {
    return '$count min';
  }

  @override
  String paEveryHours(int count) {
    return '$count h';
  }

  @override
  String get paJustNow => 'just now';

  @override
  String paMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String paHoursAgo(int count) {
    return '$count h ago';
  }

  @override
  String paDaysAgo(int count) {
    return '$count d ago';
  }

  @override
  String get paTitle => 'Auto-refresh';

  @override
  String get paAutoTitle => 'Refresh automatically';

  @override
  String get paAutoSubtitle => 'Pull new tracks from the sources on a schedule';

  @override
  String get paOnStartTitle => 'Check on launch';

  @override
  String get paOnStartSubtitle => 'One pass a few seconds after start';

  @override
  String get paPlaylistsWithSources => 'Playlists with sources';

  @override
  String get paSelectAll => 'Select all';

  @override
  String get paDeselectAll => 'Clear all';

  @override
  String get paNothingToRefresh =>
      'Nothing to refresh: no playlist was imported from a link. Paste a link into the search field — an imported playlist remembers its source.';

  @override
  String get paRefreshing => 'Refreshing…';

  @override
  String get paNeverRefreshed => 'Never refreshed';

  @override
  String paLastRun(String ago) {
    return 'Last pass: $ago';
  }

  @override
  String get paSoon => 'any moment';

  @override
  String paNextIn(String time) {
    return 'in $time';
  }

  @override
  String paSelected(int selected, int total) {
    return 'Selected: $selected of $total';
  }

  @override
  String get paPeriod => 'Frequency';

  @override
  String get paRunUpdating => 'refreshing…';

  @override
  String get paRunError => 'error';

  @override
  String get paRunNoChanges => 'no changes';

  @override
  String get paRefreshNow => 'Refresh now';

  @override
  String paBusy(int count) {
    return 'Refreshing $count…';
  }

  @override
  String paProgress(int done, int total) {
    return 'Refreshing: $done/$total';
  }

  @override
  String paNewTracks(int added, int playlists) {
    return 'New tracks: $added (playlists: $playlists)';
  }

  @override
  String paFailed(int count) {
    return 'Couldn’t refresh playlists: $count';
  }

  @override
  String get paNoNewTracks => 'No new tracks';

  @override
  String rpBusy(String name) {
    return 'Refreshing “$name”…';
  }

  @override
  String get rpNoAnswer => 'The source didn’t respond';

  @override
  String rpNewTracks(int count) {
    return 'New tracks: $count';
  }

  @override
  String get iuUnrecognized => 'Couldn’t make sense of that link';

  @override
  String iuLikesTitle(String name) {
    return 'Likes · $name';
  }

  @override
  String get iuOnlySupported =>
      'Only a playlist, an album or likes can be pasted';

  @override
  String get iuNoTracks => 'That link has no tracks';

  @override
  String get iuPlaylistGone => 'That playlist no longer exists';

  @override
  String get ofRemoved => 'Removed from offline';

  @override
  String get ofSaving => 'Saving for offline…';

  @override
  String ofAvailable(String name) {
    return 'Available offline: $name';
  }

  @override
  String get ofNothingToSave => 'Nothing here to save offline';

  @override
  String get ofDownloadingTrack => 'Downloading track…';

  @override
  String ofSaved(String path) {
    return 'Saved: $path';
  }

  @override
  String get ofDownloadingFiles => 'Downloading files…';

  @override
  String get ofNothingToDownload => 'Nothing here to download';

  @override
  String get ofNoCopies => 'There were no offline copies';

  @override
  String ofRemovedCount(int count) {
    return 'Removed from offline: $count';
  }

  @override
  String ofSavingProgress(int done, int total) {
    return 'Saving: $done/$total';
  }

  @override
  String get ofAbort => 'Stop';

  @override
  String get ofNoStorage => 'No access to storage';

  @override
  String get ofCantSaveTrack => 'This track can’t be saved offline';

  @override
  String get ofBusyWithAnother => 'Already downloading another list';

  @override
  String ofDownloadedAll(int count) {
    return 'Tracks downloaded: $count';
  }

  @override
  String get ofDownloadedNone => 'Couldn’t download a single track';

  @override
  String ofDownloadedPartial(int ok, int total, int failed) {
    return 'Downloaded $ok of $total, failed: $failed';
  }

  @override
  String get ofStreamOnly => 'This track is stream-only — it can’t be saved';

  @override
  String get ofDrm => 'The track is DRM-protected';

  @override
  String get ofNoFileLink => 'The source didn’t return a file link';

  @override
  String get ofNoConnection => 'No connection';

  @override
  String ofSaveFailed(String message) {
    return 'Couldn’t save: $message';
  }

  @override
  String get fdPathIos => 'Files → On My iPhone → Bloom';

  @override
  String get fdPathAndroid => 'Music/Bloom';

  @override
  String get fdCantDownload => 'This track can’t be downloaded';

  @override
  String get fdNeedPermission =>
      'Storage access is required — allow it and try again';

  @override
  String get fdSaveFailed => 'Couldn’t save the file';

  @override
  String get fdDownloadFile => 'Download as a file';

  @override
  String get taRemoveFromFavorites => 'Remove from likes';

  @override
  String get taAddToFavorites => 'Like';

  @override
  String get taAddToPlaylist => 'Add to playlist';

  @override
  String get taListenOffline => 'Listen offline';

  @override
  String get taRemoveOffline => 'Remove from offline';

  @override
  String get taGoToArtist => 'Go to artist';

  @override
  String get taDeleteTrack => 'Delete track';

  @override
  String get taTrackDeleted => 'Track deleted';

  @override
  String get taAddedToLibrary => 'Added to library';

  @override
  String get searchTabAll => 'Everything';

  @override
  String get searchHint => 'Search';

  @override
  String get searchSource => 'Source';

  @override
  String get searchSourceAll => 'All sources';

  @override
  String get searchNothingFound => 'Nothing found';

  @override
  String get searchFindSomething => 'Find something';

  @override
  String get searchSectionEmpty => 'Nothing found in this section';

  @override
  String pvLikesOf(String name) {
    return '$name’s likes';
  }

  @override
  String pvPlaylistCreated(String tracks) {
    return 'Playlist created — $tracks';
  }

  @override
  String pvImporting(int count) {
    return 'Importing $count…';
  }

  @override
  String pvImportProgress(int done, int total) {
    return 'Importing: $done/$total';
  }

  @override
  String pvImported(int ok, int total) {
    return 'Imported: $ok of $total';
  }

  @override
  String pvPlaylistsTitle(int count) {
    return 'Playlists · $count';
  }

  @override
  String get pvImportAll => 'Import all';

  @override
  String pvLikesTitle(int count) {
    return 'Likes · $count';
  }

  @override
  String get pvToPlaylist => 'To a playlist';

  @override
  String get pvNothingPublic => 'This account has no public playlists or likes';

  @override
  String pvAdded(String tracks) {
    return 'Added: $tracks';
  }

  @override
  String get profileDefaultName => 'Listener';

  @override
  String get profileNickCopied => 'Nickname copied!';

  @override
  String get profileStats => 'Statistics';

  @override
  String get profileAchievements => 'Achievements';

  @override
  String get profileNowPlaying => 'Now playing: ';

  @override
  String get profileSaved => 'Profile saved!';

  @override
  String get profileNickname => 'NICKNAME';

  @override
  String get profileNicknameHint => 'Enter a nickname...';

  @override
  String get profileAbout => 'ABOUT';

  @override
  String get profileAboutHint => 'Tell us about yourself...';

  @override
  String get profileStatus => 'STATUS';

  @override
  String get profileStatusHint => '\"My status...\"';

  @override
  String get profileDisc => 'DISC';

  @override
  String get profileColorSolid => 'Color';

  @override
  String get profileColorGradient => 'Gradient';

  @override
  String get profileRemoveImage => 'Remove image';

  @override
  String get profileRemovePhoto => 'Remove photo';

  @override
  String profileZoom(int percent) {
    return 'Zoom  $percent%';
  }

  @override
  String achUnlockedToast(String name, String tier) {
    return '🏅 Achievement unlocked: $name — $tier';
  }

  @override
  String get achMax => 'Maxed out';

  @override
  String achUnlockedAt(String date) {
    return 'earned $date';
  }

  @override
  String get achTierBronze => 'Bronze';

  @override
  String get achTierSilver => 'Silver';

  @override
  String get achTierGold => 'Gold';

  @override
  String get achListenerName => 'Music Lover';

  @override
  String get achListenerDesc => 'Total plays';

  @override
  String get achTimeName => 'In the Headphones';

  @override
  String get achTimeDesc => 'Listening time';

  @override
  String get achStreakName => 'On a Roll';

  @override
  String get achStreakDesc => 'Days in a row with plays';

  @override
  String get achMarathonName => 'Marathoner';

  @override
  String get achMarathonDesc => 'Tracks in a single day';

  @override
  String get achVeteranName => 'Bloom Veteran';

  @override
  String get achVeteranDesc => 'Time in the app';

  @override
  String get achDevoteeName => 'Devotion';

  @override
  String get achDevoteeDesc => 'Active days total';

  @override
  String get statsTracks => 'Tracks';

  @override
  String get statsPlays => 'Plays';

  @override
  String get statsTime => 'Listening time';

  @override
  String get statsUnique => 'Unique';

  @override
  String get statsAvgLength => 'Average length';

  @override
  String get statsFavArtist => 'Favorite artist';

  @override
  String get statsAppTime => 'Time in app';

  @override
  String get statsRecordDay => 'Day record';

  @override
  String get statsAvgPerDay => 'Daily average';

  @override
  String get statsHoursDay => 'hours/day';

  @override
  String get statsTracksDay => 'tracks/day';

  @override
  String get statsArtists => 'artists';

  @override
  String get statsSources => 'Where you listen most';

  @override
  String get statsTopTracks => 'Top tracks';

  @override
  String get statsActivity => 'Activity';

  @override
  String get statsTopArtists => 'Top artists';

  @override
  String get statsLocalFiles => 'Local files';

  @override
  String get statsNoDataYet => 'No data yet';

  @override
  String get statsFootnote =>
      'Counted from the listening history on this device';

  @override
  String get statsCopy => 'Copy';

  @override
  String get statsClear => 'Clear';

  @override
  String get statsClearConfirm => 'Sure? Tap again';

  @override
  String get statsCopied => 'Statistics copied';

  @override
  String get statsCleared => 'Statistics cleared';

  @override
  String get statsToday => 'Today';

  @override
  String get statsPeriod7d => '7d';

  @override
  String get statsPeriod30d => '30d';

  @override
  String get statsPeriodAll => 'All';

  @override
  String get statsLess => 'less';

  @override
  String get statsMore => 'more';

  @override
  String get statsZeroMinutes => '0 min';

  @override
  String statsHoursMinutes(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String statsMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get statsShareTitle => '🎵 My Bloom stats';

  @override
  String statsShareTracks(int count) {
    return '📚 Tracks: $count';
  }

  @override
  String statsShareUnique(int count) {
    return '🎵 Unique: $count';
  }

  @override
  String statsSharePlays(int count) {
    return '▶️ Played: $count';
  }

  @override
  String statsShareTime(String value) {
    return '🎧 Listening time: $value';
  }

  @override
  String statsShareAvgLength(String value) {
    return '📏 Average length: $value';
  }

  @override
  String statsShareAppTime(String value) {
    return '⏱️ Time in app: $value';
  }

  @override
  String statsShareFavArtist(String name) {
    return '⭐ Favorite artist: $name';
  }

  @override
  String statsShareRecordDay(int count) {
    return '🏆 Day record: $count';
  }

  @override
  String get statsShareAvgPerDay => '📈 Daily average:';

  @override
  String get statsShareSources => '📡 Where you listened most:';

  @override
  String get statsShareTopTracks => '🔥 Top tracks:';

  @override
  String get statsShareTopArtists => '👤 Top artists:';

  @override
  String get setGroupMain => 'GENERAL';

  @override
  String get setGroupAppearance => 'APPEARANCE';

  @override
  String get setGroupIntegrations => 'INTEGRATIONS';

  @override
  String get setSystem => 'System';

  @override
  String get setAudio => 'Audio';

  @override
  String get setSwipes => 'Swipes';

  @override
  String get setStorage => 'Storage';

  @override
  String get setPlayer => 'Player';

  @override
  String get setInterface => 'Interface';

  @override
  String get setCustomization => 'Customization';

  @override
  String setStub(String title) {
    return '“$title” isn’t built yet';
  }

  @override
  String get swZoneLibrary => 'Library';

  @override
  String get swZoneQueue => 'Queue';

  @override
  String get swZoneMini => 'Mini player';

  @override
  String get swZonePlayer => 'Player';

  @override
  String get swLeft => 'Swipe left';

  @override
  String get swRight => 'Swipe right';

  @override
  String get swActNone => 'Disabled';

  @override
  String get swActLike => 'Like';

  @override
  String get swActQueue => 'Add to queue';

  @override
  String get swActPlayNext => 'Play next';

  @override
  String get swActNext => 'Next';

  @override
  String get swActPrev => 'Previous';

  @override
  String get swActDownload => 'Download';

  @override
  String get swActDelete => 'Delete';

  @override
  String get swAddedToQueue => 'Added to queue';

  @override
  String get swAlreadyInQueue => 'Already in the queue';

  @override
  String get swPlaysNext => 'Plays next';

  @override
  String get swLiked => 'Added to favorites';

  @override
  String get swUnliked => 'Removed from favorites';

  @override
  String get swRemoved => 'Removed';

  @override
  String get apLanguage => 'LANGUAGE';

  @override
  String get apLanguageRu => 'Русский';

  @override
  String get apLanguageEn => 'English';

  @override
  String get apTheme => 'THEME';

  @override
  String get apThemeRow => 'Theme';

  @override
  String get thNew => 'Custom theme';

  @override
  String get thNameDefault => 'My theme';

  @override
  String get thSlotBg => 'Background';

  @override
  String get thSlotCard => 'Card';

  @override
  String get thSlotAccent => 'Accent';

  @override
  String get thRandom => 'Random colors';

  @override
  String thCreated(String name) {
    return 'Theme “$name” created';
  }

  @override
  String get thDeleted => 'Preset deleted';

  @override
  String get apAutoAccent => 'Auto accent';

  @override
  String get apAutoAccentSub => 'Accent color from the track cover';

  @override
  String get apAutoAccentLevel => 'Accent brightness';

  @override
  String get apCorners => 'CORNERS';

  @override
  String get apPreviewTitle => 'A block looks like this';

  @override
  String get apPreviewSubtitle => 'and secondary text';

  @override
  String get apBadgesTitle => 'Badges in accent color';

  @override
  String get apBadgesSubtitle =>
      'Source badges use their brand colors by default; enable to tint them with the accent';

  @override
  String get scHelp =>
      'Usually not needed: the key is picked up automatically — by scraping the site, and failing that by trying known ones. Setting your own makes sense if SoundCloud stopped responding.';

  @override
  String get scHint => 'Automatic';

  @override
  String get scCheckConnection => 'Check connection';

  @override
  String get scConnectionOk => 'Connection works';

  @override
  String get scConnectionFail => 'Not responding';

  @override
  String get scActiveKey => 'Active key';

  @override
  String get ymChecking => 'Checking…';

  @override
  String get ymConnected => '✓ Connected';

  @override
  String get ymNotConnected => 'Not connected';

  @override
  String get ymLogout => 'Log out';

  @override
  String get ymPlusActiveA => 'Yandex Plus active';

  @override
  String get ymPlusActiveB => '— tracks play directly from Yandex.';

  @override
  String get ymPlusNoneA => 'No Plus';

  @override
  String get ymPlusNoneB => '— some tracks may be unavailable for playback.';

  @override
  String get ymPlusUnknown => 'Subscription status unknown.';

  @override
  String get ymLoginHint =>
      'Sign in with your Yandex ID. A confirmation page will open — enter the code there.';

  @override
  String get ymConnect => 'Connect Yandex Music';

  @override
  String get ymCodePromptA => 'Open';

  @override
  String get ymCodePromptB => 'and enter the code:';

  @override
  String get ymOpenPage => 'Open the page';

  @override
  String get ymCodeCopied => 'Code copied';

  @override
  String get ymGettingCode => 'Getting code…';

  @override
  String get ymWaiting => 'Waiting for confirmation…';

  @override
  String get ymCodeExpired => 'Code expired — press “Connect” again.';

  @override
  String get ymErrAuth => 'Yandex Music token is invalid — sign in again';

  @override
  String get ymErrNeedPlus =>
      'Track unavailable — Yandex Plus subscription required';

  @override
  String get ymErrNetwork => 'Yandex is not responding';

  @override
  String get ytmConfigured => 'Configured';

  @override
  String get ytmNoAuth => 'No authentication needed for now';

  @override
  String get ytmHelp =>
      'Search, pages and link import work without auth. Playback and downloads come straight from YouTube.';

  @override
  String get stOfflineCache => 'Offline track cache';

  @override
  String get stCounting => 'Counting…';

  @override
  String stCacheStats(int count, String size) {
    return '$count tracks · $size';
  }

  @override
  String get stHelp =>
      'Downloaded tracks play without a network and use no data. They live inside the app — other players can’t see them, and they are removed together with Bloom.';

  @override
  String get stClear => 'Clear offline cache';

  @override
  String get stClearTitle => 'Clear the offline cache?';

  @override
  String get stClearBody =>
      'The downloaded copies will be deleted and those tracks will stop playing without a network. They stay in your library and playlists.';

  @override
  String stCleared(int count) {
    return 'Offline cache cleared, files deleted: $count';
  }

  @override
  String stBytes(String value) {
    return '$value B';
  }

  @override
  String stKilobytes(String value) {
    return '$value KB';
  }

  @override
  String stMegabytes(String value) {
    return '$value MB';
  }

  @override
  String stGigabytes(String value) {
    return '$value GB';
  }
}
