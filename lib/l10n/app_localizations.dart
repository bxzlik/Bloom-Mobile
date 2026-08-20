import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// desktop: common.undo — default toast action label
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get commonUpload;

  /// phone only: collapses the setup block on a platform page
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get commonHide;

  /// No description provided for @commonClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get commonClear;

  /// phone only: separator between the guide card and manual input
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get commonOr;

  /// desktop: settings.interface.titlebar.item.pin
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get commonPin;

  /// desktop: lib.sidebar.unpin
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get commonUnpin;

  /// desktop: player.aria.play
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get commonPlay;

  /// phone only: resumes the paused track from the home tab menu
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// desktop: player.aria.shuffle
  ///
  /// In en, this message translates to:
  /// **'Shuffle'**
  String get commonShuffle;

  /// desktop: search.follow
  ///
  /// In en, this message translates to:
  /// **'Follow'**
  String get commonFollow;

  /// desktop: search.unfollow
  ///
  /// In en, this message translates to:
  /// **'Unfollow'**
  String get commonUnfollow;

  /// desktop: share.copyLink
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get commonCopyLink;

  /// desktop: share.toast.linkCopied
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get commonLinkCopied;

  /// desktop: search.loadMore
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get commonLoadMore;

  /// No description provided for @commonShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get commonShowMore;

  /// No description provided for @commonAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get commonAlbum;

  /// No description provided for @commonPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Playlist'**
  String get commonPlaylist;

  /// No description provided for @commonArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get commonArtist;

  /// desktop: search.tab.tracks
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get commonTracks;

  /// No description provided for @commonPlaylists.
  ///
  /// In en, this message translates to:
  /// **'Playlists'**
  String get commonPlaylists;

  /// desktop: search.tab.albums
  ///
  /// In en, this message translates to:
  /// **'Albums'**
  String get commonAlbums;

  /// desktop: search.tab.artists
  ///
  /// In en, this message translates to:
  /// **'Artists'**
  String get commonArtists;

  /// desktop: player.queueTitle.all
  ///
  /// In en, this message translates to:
  /// **'All tracks'**
  String get commonAllTracks;

  /// desktop: player.queueTitle.fav
  ///
  /// In en, this message translates to:
  /// **'Liked'**
  String get commonFavorites;

  /// desktop: settings.home.item.history
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get commonHistory;

  /// No description provided for @commonLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get commonLibrary;

  /// desktop: lib.plmenu.sort
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get commonSort;

  /// desktop: player.add.newPlaylist
  ///
  /// In en, this message translates to:
  /// **'New playlist'**
  String get commonNewPlaylist;

  /// desktop: player.add.createPlaylist
  ///
  /// In en, this message translates to:
  /// **'Create playlist'**
  String get commonCreatePlaylist;

  /// desktop: player.add.toLib
  ///
  /// In en, this message translates to:
  /// **'Add to library'**
  String get commonAddToLibrary;

  /// No description provided for @commonAlreadyInLibrary.
  ///
  /// In en, this message translates to:
  /// **'Already in your library'**
  String get commonAlreadyInLibrary;

  /// desktop: common.unknownArtist — a local file whose tags carry no artist
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknownArtist;

  /// desktop: lib.plmenu.offlineBadge
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get commonOfflineBadge;

  /// Replaces the hand-rolled tracksCount() from shared/util/format.dart
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} track} other{{count} tracks}}'**
  String tracksCount(int count);

  /// formatted is the already-compacted number (1.2K); count drives the plural form
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{formatted} follower} other{{formatted} followers}}'**
  String followersCount(int count, String formatted);

  /// desktop: stats.playsCount
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} play} other{{count} plays}}'**
  String playsCount(int count);

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @sourceLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get sourceLocal;

  /// desktop: settings.nav.yandex
  ///
  /// In en, this message translates to:
  /// **'Yandex Music'**
  String get sourceYandex;

  /// No description provided for @homeRecent.
  ///
  /// In en, this message translates to:
  /// **'Recently played'**
  String get homeRecent;

  /// No description provided for @homeCharts.
  ///
  /// In en, this message translates to:
  /// **'Charts'**
  String get homeCharts;

  /// No description provided for @homeNewReleases.
  ///
  /// In en, this message translates to:
  /// **'New releases'**
  String get homeNewReleases;

  /// desktop: settings.view.mpEl.queue
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get playerQueue;

  /// Подпись источника очереди, набранной из выдачи поиска
  ///
  /// In en, this message translates to:
  /// **'Search: {query}'**
  String playerSourceSearch(String query);

  /// desktop: player.toast.copied
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get playerCopied;

  /// desktop: player.toast.copyError
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get playerCopyError;

  /// desktop: player.aria.speed (Playback speed)
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get playerSpeed;

  /// desktop: player.speed.custom
  ///
  /// In en, this message translates to:
  /// **'Custom speed'**
  String get playerSpeedCustom;

  /// desktop: player.speed.reset
  ///
  /// In en, this message translates to:
  /// **'Reset to 1×'**
  String get playerSpeedReset;

  /// desktop: player.speed.nightcore
  ///
  /// In en, this message translates to:
  /// **'Nightcore'**
  String get playerSpeedNightcore;

  /// desktop: player.speed.nightcoreSub
  ///
  /// In en, this message translates to:
  /// **'Pitch follows the speed'**
  String get playerSpeedNightcoreSub;

  /// Мобильная фича, десктопного оригинала нет
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get playerSleep;

  /// Подпись под числом на карточке-пресете таймера сна
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get playerSleepMin;

  /// Время таймера сна в пилюле и на краях полосы
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String playerSleepMinutes(int count);

  /// Остаток таймера сна в шапке шторки
  ///
  /// In en, this message translates to:
  /// **'{time} left'**
  String playerSleepLeft(String time);

  /// No description provided for @playerSleepEndOfTrack.
  ///
  /// In en, this message translates to:
  /// **'Until end of track'**
  String get playerSleepEndOfTrack;

  /// No description provided for @playerSleepCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom time'**
  String get playerSleepCustom;

  /// No description provided for @playerSleepExtend.
  ///
  /// In en, this message translates to:
  /// **'+5 minutes'**
  String get playerSleepExtend;

  /// No description provided for @playerSleepCancel.
  ///
  /// In en, this message translates to:
  /// **'Turn off timer'**
  String get playerSleepCancel;

  /// No description provided for @playerSleepFade.
  ///
  /// In en, this message translates to:
  /// **'Fade out'**
  String get playerSleepFade;

  /// No description provided for @playerSleepFadeSub.
  ///
  /// In en, this message translates to:
  /// **'Volume drops to zero over the last 20 seconds'**
  String get playerSleepFadeSub;

  /// No description provided for @notifChannelName.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get notifChannelName;

  /// No description provided for @notifChannelDescription.
  ///
  /// In en, this message translates to:
  /// **'Music controls in the notification shade and on the lock screen'**
  String get notifChannelDescription;

  /// No description provided for @artistSourceNotConnected.
  ///
  /// In en, this message translates to:
  /// **'This artist’s source isn’t connected'**
  String get artistSourceNotConnected;

  /// No description provided for @artistNotFound.
  ///
  /// In en, this message translates to:
  /// **'Artist not found'**
  String get artistNotFound;

  /// desktop: search.popular
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get artistPopular;

  /// desktop: search.tab.reposts
  ///
  /// In en, this message translates to:
  /// **'Reposts'**
  String get artistReposts;

  /// desktop: search.similarArtists
  ///
  /// In en, this message translates to:
  /// **'Fans might also like'**
  String get artistSimilar;

  /// No description provided for @artistNoTracks.
  ///
  /// In en, this message translates to:
  /// **'This artist has no available tracks'**
  String get artistNoTracks;

  /// No description provided for @artistTracksToNewPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Tracks to a new playlist'**
  String get artistTracksToNewPlaylist;

  /// No description provided for @artistNotFoundOnSource.
  ///
  /// In en, this message translates to:
  /// **'Not found on the source'**
  String get artistNotFoundOnSource;

  /// No description provided for @followedToast.
  ///
  /// In en, this message translates to:
  /// **'Following {name}'**
  String followedToast(String name);

  /// No description provided for @unfollowedToast.
  ///
  /// In en, this message translates to:
  /// **'Unfollowed'**
  String get unfollowedToast;

  /// tracks is an already-formatted tracksCount string
  ///
  /// In en, this message translates to:
  /// **'Added: {title} — {tracks}'**
  String addedToast(String title, String tracks);

  /// No description provided for @setSourceNotConnected.
  ///
  /// In en, this message translates to:
  /// **'This list’s source isn’t connected'**
  String get setSourceNotConnected;

  /// No description provided for @setAlbumNotFound.
  ///
  /// In en, this message translates to:
  /// **'Album not found'**
  String get setAlbumNotFound;

  /// No description provided for @setPlaylistNotFound.
  ///
  /// In en, this message translates to:
  /// **'Playlist not found'**
  String get setPlaylistNotFound;

  /// No description provided for @setNoTracks.
  ///
  /// In en, this message translates to:
  /// **'No tracks available'**
  String get setNoTracks;

  /// No description provided for @setSaveToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Save to library'**
  String get setSaveToLibrary;

  /// No description provided for @libFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get libFilterAll;

  /// No description provided for @libEmptyArtists.
  ///
  /// In en, this message translates to:
  /// **'No subscriptions yet'**
  String get libEmptyArtists;

  /// No description provided for @libEmptyPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No playlists yet'**
  String get libEmptyPlaylists;

  /// No description provided for @libEmptyAll.
  ///
  /// In en, this message translates to:
  /// **'Create a playlist or paste a link into search'**
  String get libEmptyAll;

  /// No description provided for @libAutoRefreshTooltip.
  ///
  /// In en, this message translates to:
  /// **'Playlist auto-refresh'**
  String get libAutoRefreshTooltip;

  /// No description provided for @libSortManual.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get libSortManual;

  /// No description provided for @libSortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'By name A–Z'**
  String get libSortNameAsc;

  /// No description provided for @libSortNameDesc.
  ///
  /// In en, this message translates to:
  /// **'By name Z–A'**
  String get libSortNameDesc;

  /// No description provided for @libSortType.
  ///
  /// In en, this message translates to:
  /// **'By type'**
  String get libSortType;

  /// No description provided for @tlSortManual.
  ///
  /// In en, this message translates to:
  /// **'In order'**
  String get tlSortManual;

  /// No description provided for @tlSortName.
  ///
  /// In en, this message translates to:
  /// **'By title'**
  String get tlSortName;

  /// No description provided for @tlSortArtist.
  ///
  /// In en, this message translates to:
  /// **'By artist'**
  String get tlSortArtist;

  /// No description provided for @tlSortDuration.
  ///
  /// In en, this message translates to:
  /// **'By length'**
  String get tlSortDuration;

  /// No description provided for @tlNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get tlNothingFound;

  /// No description provided for @tlEmptyFav.
  ///
  /// In en, this message translates to:
  /// **'Nothing liked yet'**
  String get tlEmptyFav;

  /// No description provided for @tlEmptyHistory.
  ///
  /// In en, this message translates to:
  /// **'History is empty'**
  String get tlEmptyHistory;

  /// desktop: historyLabel() group header in the History view
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get histToday;

  /// No description provided for @histYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get histYesterday;

  /// No description provided for @histDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} day ago} other{{count} days ago}}'**
  String histDaysAgo(int count);

  /// No description provided for @histWeekAgo.
  ///
  /// In en, this message translates to:
  /// **'A week ago'**
  String get histWeekAgo;

  /// No description provided for @tlEmptyAll.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty'**
  String get tlEmptyAll;

  /// No description provided for @tlEmptyPlaylist.
  ///
  /// In en, this message translates to:
  /// **'This playlist is empty'**
  String get tlEmptyPlaylist;

  /// No description provided for @tlSearchHint.
  ///
  /// In en, this message translates to:
  /// **'In this list'**
  String get tlSearchHint;

  /// No description provided for @tlStopSaving.
  ///
  /// In en, this message translates to:
  /// **'Stop saving'**
  String get tlStopSaving;

  /// desktop: lib.plmenu.removeOfflinePlaylist
  ///
  /// In en, this message translates to:
  /// **'Remove from offline'**
  String get tlRemoveOffline;

  /// No description provided for @tlListenOffline.
  ///
  /// In en, this message translates to:
  /// **'Listen offline ({count})'**
  String tlListenOffline(int count);

  /// No description provided for @tlDownloadFiles.
  ///
  /// In en, this message translates to:
  /// **'Download as files ({count})'**
  String tlDownloadFiles(int count);

  /// No description provided for @tlRefreshTracks.
  ///
  /// In en, this message translates to:
  /// **'Refresh tracks'**
  String get tlRefreshTracks;

  /// desktop: lib.plmenu.toQueue — append the whole list to the queue
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get tlToQueue;

  /// desktop: lib.plmenu.playNext
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get tlPlayNext;

  /// desktop: toast.addedToQueue
  ///
  /// In en, this message translates to:
  /// **'Added to queue: {count}'**
  String tlQueuedTracks(int count);

  /// desktop: toast.queuedNext
  ///
  /// In en, this message translates to:
  /// **'Playing next: {count}'**
  String tlQueuedNext(int count);

  /// desktop: lib.plmenu.exportPlaylist
  ///
  /// In en, this message translates to:
  /// **'Export playlist'**
  String get tlExportPlaylist;

  /// No description provided for @tlDeletePlaylist.
  ///
  /// In en, this message translates to:
  /// **'Delete playlist'**
  String get tlDeletePlaylist;

  /// No description provided for @tlPlaylistDeleted.
  ///
  /// In en, this message translates to:
  /// **'Playlist “{name}” deleted'**
  String tlPlaylistDeleted(String name);

  /// desktop: lib.plmenu.deletePlaylistWithTracks
  ///
  /// In en, this message translates to:
  /// **'Delete playlist and tracks'**
  String get tlDeletePlaylistWithTracks;

  /// No description provided for @tlPlaylistAndTracksDeleted.
  ///
  /// In en, this message translates to:
  /// **'Playlist “{name}” and its tracks deleted'**
  String tlPlaylistAndTracksDeleted(String name);

  /// No description provided for @leAlreadyFavorite.
  ///
  /// In en, this message translates to:
  /// **'Already liked'**
  String get leAlreadyFavorite;

  /// No description provided for @leAddedToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Liked: {tracks}'**
  String leAddedToFavorites(String tracks);

  /// No description provided for @leDeleteArm.
  ///
  /// In en, this message translates to:
  /// **'Tap again — {tracks} will be gone everywhere'**
  String leDeleteArm(String tracks);

  /// No description provided for @leDiscardArm.
  ///
  /// In en, this message translates to:
  /// **'Tap again to discard your changes'**
  String get leDiscardArm;

  /// No description provided for @cpImported.
  ///
  /// In en, this message translates to:
  /// **'Imported: {title} — {count}'**
  String cpImported(String title, int count);

  /// No description provided for @cpAllAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'All of it is already in your library'**
  String get cpAllAlreadyIn;

  /// No description provided for @cpAdded.
  ///
  /// In en, this message translates to:
  /// **'Added: {count}'**
  String cpAdded(int count);

  /// No description provided for @cpSourceNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'The source didn’t respond'**
  String get cpSourceNoAnswer;

  /// No description provided for @cpNameHint.
  ///
  /// In en, this message translates to:
  /// **'My playlist'**
  String get cpNameHint;

  /// No description provided for @cpImportByLink.
  ///
  /// In en, this message translates to:
  /// **'Import from a link'**
  String get cpImportByLink;

  /// No description provided for @cpLinkHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a link…'**
  String get cpLinkHint;

  /// No description provided for @cpDestination.
  ///
  /// In en, this message translates to:
  /// **'To: {target}'**
  String cpDestination(String target);

  /// No description provided for @paEveryMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String paEveryMinutes(int count);

  /// No description provided for @paEveryHours.
  ///
  /// In en, this message translates to:
  /// **'{count} h'**
  String paEveryHours(int count);

  /// No description provided for @paJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get paJustNow;

  /// No description provided for @paMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String paMinutesAgo(int count);

  /// No description provided for @paHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} h ago'**
  String paHoursAgo(int count);

  /// No description provided for @paDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} d ago'**
  String paDaysAgo(int count);

  /// No description provided for @paTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-refresh'**
  String get paTitle;

  /// No description provided for @paAutoTitle.
  ///
  /// In en, this message translates to:
  /// **'Refresh automatically'**
  String get paAutoTitle;

  /// No description provided for @paAutoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pull new tracks from the sources on a schedule'**
  String get paAutoSubtitle;

  /// No description provided for @paOnStartTitle.
  ///
  /// In en, this message translates to:
  /// **'Check on launch'**
  String get paOnStartTitle;

  /// No description provided for @paOnStartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'One pass a few seconds after start'**
  String get paOnStartSubtitle;

  /// No description provided for @paPlaylistsWithSources.
  ///
  /// In en, this message translates to:
  /// **'Playlists with sources'**
  String get paPlaylistsWithSources;

  /// No description provided for @paSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get paSelectAll;

  /// No description provided for @paDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get paDeselectAll;

  /// No description provided for @paNothingToRefresh.
  ///
  /// In en, this message translates to:
  /// **'Nothing to refresh: no playlist has sources yet. Link one while editing a playlist — or import a playlist from a link and it remembers its own.'**
  String get paNothingToRefresh;

  /// No description provided for @paRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing…'**
  String get paRefreshing;

  /// No description provided for @paNeverRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Never refreshed'**
  String get paNeverRefreshed;

  /// No description provided for @paLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last pass: {ago}'**
  String paLastRun(String ago);

  /// No description provided for @paSoon.
  ///
  /// In en, this message translates to:
  /// **'any moment'**
  String get paSoon;

  /// No description provided for @paNextIn.
  ///
  /// In en, this message translates to:
  /// **'in {time}'**
  String paNextIn(String time);

  /// No description provided for @paSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected: {selected} of {total}'**
  String paSelected(int selected, int total);

  /// No description provided for @paPeriod.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get paPeriod;

  /// No description provided for @paRunUpdating.
  ///
  /// In en, this message translates to:
  /// **'refreshing…'**
  String get paRunUpdating;

  /// No description provided for @paRunError.
  ///
  /// In en, this message translates to:
  /// **'error'**
  String get paRunError;

  /// No description provided for @paRunNoChanges.
  ///
  /// In en, this message translates to:
  /// **'no changes'**
  String get paRunNoChanges;

  /// No description provided for @paRefreshNow.
  ///
  /// In en, this message translates to:
  /// **'Refresh now'**
  String get paRefreshNow;

  /// No description provided for @paBusy.
  ///
  /// In en, this message translates to:
  /// **'Refreshing {count}…'**
  String paBusy(int count);

  /// No description provided for @paProgress.
  ///
  /// In en, this message translates to:
  /// **'Refreshing: {done}/{total}'**
  String paProgress(int done, int total);

  /// No description provided for @paNewTracks.
  ///
  /// In en, this message translates to:
  /// **'New tracks: {added} (playlists: {playlists})'**
  String paNewTracks(int added, int playlists);

  /// No description provided for @paFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t refresh playlists: {count}'**
  String paFailed(int count);

  /// No description provided for @paNoNewTracks.
  ///
  /// In en, this message translates to:
  /// **'No new tracks'**
  String get paNoNewTracks;

  /// No description provided for @rpBusy.
  ///
  /// In en, this message translates to:
  /// **'Refreshing “{name}”…'**
  String rpBusy(String name);

  /// No description provided for @rpNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'The source didn’t respond'**
  String get rpNoAnswer;

  /// No description provided for @rpNewTracks.
  ///
  /// In en, this message translates to:
  /// **'New tracks: {count}'**
  String rpNewTracks(int count);

  /// No description provided for @psTitle.
  ///
  /// In en, this message translates to:
  /// **'Update sources'**
  String get psTitle;

  /// No description provided for @psHint.
  ///
  /// In en, this message translates to:
  /// **'Link playlists, albums or likes from any platform — “Refresh tracks” will add new tracks from them to the top of this playlist.'**
  String get psHint;

  /// No description provided for @psAddHint.
  ///
  /// In en, this message translates to:
  /// **'Paste a playlist, album or profile link…'**
  String get psAddHint;

  /// No description provided for @psAdd.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get psAdd;

  /// No description provided for @psRemove.
  ///
  /// In en, this message translates to:
  /// **'Unlink'**
  String get psRemove;

  /// No description provided for @psDuplicate.
  ///
  /// In en, this message translates to:
  /// **'This source is already linked'**
  String get psDuplicate;

  /// No description provided for @iuUnrecognized.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t make sense of that link'**
  String get iuUnrecognized;

  /// No description provided for @iuLikesTitle.
  ///
  /// In en, this message translates to:
  /// **'Likes · {name}'**
  String iuLikesTitle(String name);

  /// No description provided for @iuOnlySupported.
  ///
  /// In en, this message translates to:
  /// **'Only a playlist, an album or likes can be pasted'**
  String get iuOnlySupported;

  /// No description provided for @iuNoTracks.
  ///
  /// In en, this message translates to:
  /// **'That link has no tracks'**
  String get iuNoTracks;

  /// No description provided for @iuPlaylistGone.
  ///
  /// In en, this message translates to:
  /// **'That playlist no longer exists'**
  String get iuPlaylistGone;

  /// No description provided for @ofRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed from offline'**
  String get ofRemoved;

  /// No description provided for @ofSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving for offline…'**
  String get ofSaving;

  /// No description provided for @ofAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available offline: {name}'**
  String ofAvailable(String name);

  /// No description provided for @ofNothingToSave.
  ///
  /// In en, this message translates to:
  /// **'Nothing here to save offline'**
  String get ofNothingToSave;

  /// No description provided for @ofDownloadingTrack.
  ///
  /// In en, this message translates to:
  /// **'Downloading track…'**
  String get ofDownloadingTrack;

  /// No description provided for @ofSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved: {path}'**
  String ofSaved(String path);

  /// No description provided for @ofDownloadingFiles.
  ///
  /// In en, this message translates to:
  /// **'Downloading files…'**
  String get ofDownloadingFiles;

  /// No description provided for @ofNothingToDownload.
  ///
  /// In en, this message translates to:
  /// **'Nothing here to download'**
  String get ofNothingToDownload;

  /// No description provided for @ofNoCopies.
  ///
  /// In en, this message translates to:
  /// **'There were no offline copies'**
  String get ofNoCopies;

  /// No description provided for @ofRemovedCount.
  ///
  /// In en, this message translates to:
  /// **'Removed from offline: {count}'**
  String ofRemovedCount(int count);

  /// No description provided for @ofSavingProgress.
  ///
  /// In en, this message translates to:
  /// **'Saving: {done}/{total}'**
  String ofSavingProgress(int done, int total);

  /// No description provided for @ofAbort.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get ofAbort;

  /// No description provided for @ofNoStorage.
  ///
  /// In en, this message translates to:
  /// **'No access to storage'**
  String get ofNoStorage;

  /// No description provided for @ofCantSaveTrack.
  ///
  /// In en, this message translates to:
  /// **'This track can’t be saved offline'**
  String get ofCantSaveTrack;

  /// No description provided for @ofBusyWithAnother.
  ///
  /// In en, this message translates to:
  /// **'Already downloading another list'**
  String get ofBusyWithAnother;

  /// No description provided for @ofDownloadedAll.
  ///
  /// In en, this message translates to:
  /// **'Tracks downloaded: {count}'**
  String ofDownloadedAll(int count);

  /// No description provided for @ofDownloadedNone.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t download a single track'**
  String get ofDownloadedNone;

  /// No description provided for @ofDownloadedPartial.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {ok} of {total}, failed: {failed}'**
  String ofDownloadedPartial(int ok, int total, int failed);

  /// No description provided for @ofStreamOnly.
  ///
  /// In en, this message translates to:
  /// **'This track is stream-only — it can’t be saved'**
  String get ofStreamOnly;

  /// No description provided for @ofDrm.
  ///
  /// In en, this message translates to:
  /// **'The track is DRM-protected'**
  String get ofDrm;

  /// No description provided for @ofNoFileLink.
  ///
  /// In en, this message translates to:
  /// **'The source didn’t return a file link'**
  String get ofNoFileLink;

  /// No description provided for @ofNoConnection.
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get ofNoConnection;

  /// No description provided for @ofSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save: {message}'**
  String ofSaveFailed(String message);

  /// No description provided for @fdPathIos.
  ///
  /// In en, this message translates to:
  /// **'Files → On My iPhone → Bloom'**
  String get fdPathIos;

  /// No description provided for @fdPathAndroid.
  ///
  /// In en, this message translates to:
  /// **'Music/Bloom'**
  String get fdPathAndroid;

  /// No description provided for @fdCantDownload.
  ///
  /// In en, this message translates to:
  /// **'This track can’t be downloaded'**
  String get fdCantDownload;

  /// No description provided for @fdNeedPermission.
  ///
  /// In en, this message translates to:
  /// **'Storage access is required — allow it and try again'**
  String get fdNeedPermission;

  /// No description provided for @fdSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the file'**
  String get fdSaveFailed;

  /// No description provided for @fdDownloadFile.
  ///
  /// In en, this message translates to:
  /// **'Download as a file'**
  String get fdDownloadFile;

  /// desktop: lib.plmenu.convert
  ///
  /// In en, this message translates to:
  /// **'Transfer to source…'**
  String get tlConvert;

  /// desktop: lib.convert.title
  ///
  /// In en, this message translates to:
  /// **'Transfer to source'**
  String get cvTitle;

  /// No description provided for @cvScanning.
  ///
  /// In en, this message translates to:
  /// **'Looking up tracks on {source}…'**
  String cvScanning(String source);

  /// desktop: lib.convert.hint.scanning
  ///
  /// In en, this message translates to:
  /// **'You can leave — the transfer will be cancelled'**
  String get cvScanHint;

  /// No description provided for @cvSummary.
  ///
  /// In en, this message translates to:
  /// **'Moved {moved} · kept {kept} · skipped {skipped}'**
  String cvSummary(int moved, int kept, int skipped);

  /// desktop: lib.convert.takeBest
  ///
  /// In en, this message translates to:
  /// **'Take the best'**
  String get cvTakeBest;

  /// No description provided for @cvCreate.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Create a playlist of {count} track} other{Create a playlist of {count} tracks}}'**
  String cvCreate(int count);

  /// No description provided for @cvTagMoved.
  ///
  /// In en, this message translates to:
  /// **'Transferred'**
  String get cvTagMoved;

  /// No description provided for @cvTagOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get cvTagOriginal;

  /// No description provided for @cvTagOnTarget.
  ///
  /// In en, this message translates to:
  /// **'Already here'**
  String get cvTagOnTarget;

  /// No description provided for @cvTagSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get cvTagSkipped;

  /// No description provided for @cvNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found on {source}'**
  String cvNotFound(String source);

  /// No description provided for @cvSearchFailed.
  ///
  /// In en, this message translates to:
  /// **'The source didn’t answer'**
  String get cvSearchFailed;

  /// No description provided for @cvKeepOriginal.
  ///
  /// In en, this message translates to:
  /// **'Keep the original'**
  String get cvKeepOriginal;

  /// No description provided for @cvSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip this track'**
  String get cvSkip;

  /// No description provided for @cvCreated.
  ///
  /// In en, this message translates to:
  /// **'“{name}” created — {tracks}'**
  String cvCreated(String name, String tracks);

  /// desktop: lib.ctx.switchSrc
  ///
  /// In en, this message translates to:
  /// **'Switch source'**
  String get spSwitch;

  /// No description provided for @spSearching.
  ///
  /// In en, this message translates to:
  /// **'Looking on {source}…'**
  String spSearching(String source);

  /// desktop: toast.srcNow
  ///
  /// In en, this message translates to:
  /// **'Now playing from {source}'**
  String spNow(String source);

  /// desktop: toast.trackNotOnSrc
  ///
  /// In en, this message translates to:
  /// **'This track isn’t on {source}'**
  String spNotFound(String source);

  /// desktop: toast.srcSwitchFail
  ///
  /// In en, this message translates to:
  /// **'The source didn’t answer — try again'**
  String get spFailed;

  /// desktop: toast.srcUnavailable
  ///
  /// In en, this message translates to:
  /// **'This source is unavailable'**
  String get spUnavailable;

  /// desktop: lib.plmenu.mergeWith
  ///
  /// In en, this message translates to:
  /// **'Merge with…'**
  String get tlMergeWith;

  /// No description provided for @mgTitle.
  ///
  /// In en, this message translates to:
  /// **'Merging playlists'**
  String get mgTitle;

  /// No description provided for @mgNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name of the new playlist'**
  String get mgNameHint;

  /// No description provided for @mgPickHint.
  ///
  /// In en, this message translates to:
  /// **'Pick what to merge in'**
  String get mgPickHint;

  /// No description provided for @mgResult.
  ///
  /// In en, this message translates to:
  /// **'You’ll get {tracks}'**
  String mgResult(String tracks);

  /// No description provided for @mgDupsDropped.
  ///
  /// In en, this message translates to:
  /// **'−{count} repeats'**
  String mgDupsDropped(int count);

  /// No description provided for @mgDedup.
  ///
  /// In en, this message translates to:
  /// **'Remove duplicates'**
  String get mgDedup;

  /// No description provided for @mgDeleteSources.
  ///
  /// In en, this message translates to:
  /// **'Delete the originals'**
  String get mgDeleteSources;

  /// No description provided for @mgNothingToMerge.
  ///
  /// In en, this message translates to:
  /// **'There is no other playlist to merge with'**
  String get mgNothingToMerge;

  /// No description provided for @mgMerged.
  ///
  /// In en, this message translates to:
  /// **'“{name}” collected — {tracks}'**
  String mgMerged(String name, String tracks);

  /// desktop: lib.plmenu.findDups
  ///
  /// In en, this message translates to:
  /// **'Find duplicates'**
  String get tlFindDups;

  /// desktop: lib.dups.title
  ///
  /// In en, this message translates to:
  /// **'Duplicate tracks'**
  String get dupsTitle;

  /// No description provided for @dupsFound.
  ///
  /// In en, this message translates to:
  /// **'{groups, plural, one{{groups} group} other{{groups} groups}} · {extra, plural, one{{extra} extra copy} other{{extra} extra copies}}'**
  String dupsFound(int groups, int extra);

  /// No description provided for @dupsChecked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} track checked} other{{count} tracks checked}}'**
  String dupsChecked(int count);

  /// No description provided for @dupsCopies.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} copy} other{{count} copies}}'**
  String dupsCopies(int count);

  /// No description provided for @dupsPlays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} play} other{{count} plays}}'**
  String dupsPlays(int count);

  /// No description provided for @dupsKeep.
  ///
  /// In en, this message translates to:
  /// **'keep'**
  String get dupsKeep;

  /// No description provided for @dupsNone.
  ///
  /// In en, this message translates to:
  /// **'No duplicates found'**
  String get dupsNone;

  /// desktop: lib.dups.delAll
  ///
  /// In en, this message translates to:
  /// **'Remove all'**
  String get dupsDelAll;

  /// desktop: lib.dups.delGroup
  ///
  /// In en, this message translates to:
  /// **'Remove copies'**
  String get dupsDelGroup;

  /// No description provided for @dupsRemoved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} copy removed} other{{count} copies removed}}'**
  String dupsRemoved(int count);

  /// desktop: lib.ctx.trackInfo
  ///
  /// In en, this message translates to:
  /// **'Track info'**
  String get tiTitle;

  /// No description provided for @tiAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get tiAlbum;

  /// No description provided for @tiYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get tiYear;

  /// No description provided for @tiDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get tiDuration;

  /// No description provided for @tiPublisher.
  ///
  /// In en, this message translates to:
  /// **'Publisher'**
  String get tiPublisher;

  /// No description provided for @tiGenres.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get tiGenres;

  /// No description provided for @tiDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get tiDescription;

  /// No description provided for @tiFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get tiFile;

  /// desktop: TrackInfoModal ti-credited — artist as credited by the source
  ///
  /// In en, this message translates to:
  /// **'Credited'**
  String get tiCredited;

  /// No description provided for @tiExplicit.
  ///
  /// In en, this message translates to:
  /// **'Explicit lyrics'**
  String get tiExplicit;

  /// No description provided for @tiNothing.
  ///
  /// In en, this message translates to:
  /// **'The source didn’t share anything else about this track'**
  String get tiNothing;

  /// desktop: lib.ctx.toQueue
  ///
  /// In en, this message translates to:
  /// **'To queue'**
  String get taToQueue;

  /// desktop: lib.ctx.playNext
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get taPlayNext;

  /// desktop: player.aria.removeFromQueue
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get taRemoveFromQueue;

  /// desktop: lib.ctx.removeFromPl
  ///
  /// In en, this message translates to:
  /// **'Remove from playlist'**
  String get taRemoveFromPlaylist;

  /// desktop: lib.ctx.download — flyout with the two kinds of download
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get taDownload;

  /// No description provided for @taRemoveFromFavorites.
  ///
  /// In en, this message translates to:
  /// **'Remove from likes'**
  String get taRemoveFromFavorites;

  /// No description provided for @taAddToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get taAddToFavorites;

  /// No description provided for @taAddToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'Add to playlist'**
  String get taAddToPlaylist;

  /// desktop: player.dl.offline
  ///
  /// In en, this message translates to:
  /// **'Listen offline'**
  String get taListenOffline;

  /// desktop: player.dl.offlineRemove
  ///
  /// In en, this message translates to:
  /// **'Remove from offline'**
  String get taRemoveOffline;

  /// No description provided for @taGoToArtist.
  ///
  /// In en, this message translates to:
  /// **'Go to artist'**
  String get taGoToArtist;

  /// No description provided for @taDeleteTrack.
  ///
  /// In en, this message translates to:
  /// **'Delete track'**
  String get taDeleteTrack;

  /// No description provided for @taTrackDeleted.
  ///
  /// In en, this message translates to:
  /// **'Track deleted'**
  String get taTrackDeleted;

  /// No description provided for @taAddedToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Added to library'**
  String get taAddedToLibrary;

  /// desktop: search.tab.all
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get searchTabAll;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchHint;

  /// No description provided for @searchSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get searchSource;

  /// desktop: search.allSources
  ///
  /// In en, this message translates to:
  /// **'All sources'**
  String get searchSourceAll;

  /// No description provided for @searchNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get searchNothingFound;

  /// No description provided for @searchFindSomething.
  ///
  /// In en, this message translates to:
  /// **'Find something'**
  String get searchFindSomething;

  /// No description provided for @searchSectionEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing found in this section'**
  String get searchSectionEmpty;

  /// No description provided for @pvLikesOf.
  ///
  /// In en, this message translates to:
  /// **'{name}’s likes'**
  String pvLikesOf(String name);

  /// No description provided for @pvPlaylistCreated.
  ///
  /// In en, this message translates to:
  /// **'Playlist created — {tracks}'**
  String pvPlaylistCreated(String tracks);

  /// No description provided for @pvImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing {count}…'**
  String pvImporting(int count);

  /// No description provided for @pvImportProgress.
  ///
  /// In en, this message translates to:
  /// **'Importing: {done}/{total}'**
  String pvImportProgress(int done, int total);

  /// No description provided for @pvImported.
  ///
  /// In en, this message translates to:
  /// **'Imported: {ok} of {total}'**
  String pvImported(int ok, int total);

  /// No description provided for @pvPlaylistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Playlists · {count}'**
  String pvPlaylistsTitle(int count);

  /// No description provided for @pvImportAll.
  ///
  /// In en, this message translates to:
  /// **'Import all'**
  String get pvImportAll;

  /// No description provided for @pvLikesTitle.
  ///
  /// In en, this message translates to:
  /// **'Likes · {count}'**
  String pvLikesTitle(int count);

  /// No description provided for @pvToPlaylist.
  ///
  /// In en, this message translates to:
  /// **'To a playlist'**
  String get pvToPlaylist;

  /// No description provided for @pvNothingPublic.
  ///
  /// In en, this message translates to:
  /// **'This account has no public playlists or likes'**
  String get pvNothingPublic;

  /// No description provided for @pvAdded.
  ///
  /// In en, this message translates to:
  /// **'Added: {tracks}'**
  String pvAdded(String tracks);

  /// No description provided for @profileDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Listener'**
  String get profileDefaultName;

  /// No description provided for @profileNickCopied.
  ///
  /// In en, this message translates to:
  /// **'Nickname copied!'**
  String get profileNickCopied;

  /// desktop: stats.title
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get profileStats;

  /// desktop: ach.title
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get profileAchievements;

  /// No description provided for @profileNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing: '**
  String get profileNowPlaying;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved!'**
  String get profileSaved;

  /// No description provided for @profileNickname.
  ///
  /// In en, this message translates to:
  /// **'NICKNAME'**
  String get profileNickname;

  /// No description provided for @profileNicknameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a nickname...'**
  String get profileNicknameHint;

  /// No description provided for @profileAbout.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get profileAbout;

  /// No description provided for @profileAboutHint.
  ///
  /// In en, this message translates to:
  /// **'Tell us about yourself...'**
  String get profileAboutHint;

  /// No description provided for @profileStatus.
  ///
  /// In en, this message translates to:
  /// **'STATUS'**
  String get profileStatus;

  /// No description provided for @profileStatusHint.
  ///
  /// In en, this message translates to:
  /// **'\"My status...\"'**
  String get profileStatusHint;

  /// No description provided for @profileDisc.
  ///
  /// In en, this message translates to:
  /// **'DISC'**
  String get profileDisc;

  /// No description provided for @profileColorSolid.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get profileColorSolid;

  /// No description provided for @profileColorGradient.
  ///
  /// In en, this message translates to:
  /// **'Gradient'**
  String get profileColorGradient;

  /// No description provided for @profileRemoveImage.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get profileRemoveImage;

  /// No description provided for @profileRemovePhoto.
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get profileRemovePhoto;

  /// No description provided for @profileZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom  {percent}%'**
  String profileZoom(int percent);

  /// desktop: ach.unlocked
  ///
  /// In en, this message translates to:
  /// **'🏅 Achievement unlocked: {name} — {tier}'**
  String achUnlockedToast(String name, String tier);

  /// No description provided for @achMax.
  ///
  /// In en, this message translates to:
  /// **'Maxed out'**
  String get achMax;

  /// No description provided for @achUnlockedAt.
  ///
  /// In en, this message translates to:
  /// **'earned {date}'**
  String achUnlockedAt(String date);

  /// No description provided for @achTierBronze.
  ///
  /// In en, this message translates to:
  /// **'Bronze'**
  String get achTierBronze;

  /// No description provided for @achTierSilver.
  ///
  /// In en, this message translates to:
  /// **'Silver'**
  String get achTierSilver;

  /// No description provided for @achTierGold.
  ///
  /// In en, this message translates to:
  /// **'Gold'**
  String get achTierGold;

  /// No description provided for @achListenerName.
  ///
  /// In en, this message translates to:
  /// **'Music Lover'**
  String get achListenerName;

  /// No description provided for @achListenerDesc.
  ///
  /// In en, this message translates to:
  /// **'Total plays'**
  String get achListenerDesc;

  /// No description provided for @achTimeName.
  ///
  /// In en, this message translates to:
  /// **'In the Headphones'**
  String get achTimeName;

  /// No description provided for @achTimeDesc.
  ///
  /// In en, this message translates to:
  /// **'Listening time'**
  String get achTimeDesc;

  /// No description provided for @achStreakName.
  ///
  /// In en, this message translates to:
  /// **'On a Roll'**
  String get achStreakName;

  /// No description provided for @achStreakDesc.
  ///
  /// In en, this message translates to:
  /// **'Days in a row with plays'**
  String get achStreakDesc;

  /// No description provided for @achMarathonName.
  ///
  /// In en, this message translates to:
  /// **'Marathoner'**
  String get achMarathonName;

  /// No description provided for @achMarathonDesc.
  ///
  /// In en, this message translates to:
  /// **'Tracks in a single day'**
  String get achMarathonDesc;

  /// No description provided for @achVeteranName.
  ///
  /// In en, this message translates to:
  /// **'Bloom Veteran'**
  String get achVeteranName;

  /// No description provided for @achVeteranDesc.
  ///
  /// In en, this message translates to:
  /// **'Time in the app'**
  String get achVeteranDesc;

  /// No description provided for @achDevoteeName.
  ///
  /// In en, this message translates to:
  /// **'Devotion'**
  String get achDevoteeName;

  /// No description provided for @achDevoteeDesc.
  ///
  /// In en, this message translates to:
  /// **'Active days total'**
  String get achDevoteeDesc;

  /// No description provided for @statsTracks.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get statsTracks;

  /// No description provided for @statsPlays.
  ///
  /// In en, this message translates to:
  /// **'Plays'**
  String get statsPlays;

  /// No description provided for @statsTime.
  ///
  /// In en, this message translates to:
  /// **'Listening time'**
  String get statsTime;

  /// No description provided for @statsUnique.
  ///
  /// In en, this message translates to:
  /// **'Unique'**
  String get statsUnique;

  /// No description provided for @statsAvgLength.
  ///
  /// In en, this message translates to:
  /// **'Average length'**
  String get statsAvgLength;

  /// No description provided for @statsFavArtist.
  ///
  /// In en, this message translates to:
  /// **'Favorite artist'**
  String get statsFavArtist;

  /// No description provided for @statsAppTime.
  ///
  /// In en, this message translates to:
  /// **'Time in app'**
  String get statsAppTime;

  /// No description provided for @statsRecordDay.
  ///
  /// In en, this message translates to:
  /// **'Day record'**
  String get statsRecordDay;

  /// No description provided for @statsAvgPerDay.
  ///
  /// In en, this message translates to:
  /// **'Daily average'**
  String get statsAvgPerDay;

  /// No description provided for @statsHoursDay.
  ///
  /// In en, this message translates to:
  /// **'hours/day'**
  String get statsHoursDay;

  /// No description provided for @statsTracksDay.
  ///
  /// In en, this message translates to:
  /// **'tracks/day'**
  String get statsTracksDay;

  /// No description provided for @statsArtists.
  ///
  /// In en, this message translates to:
  /// **'artists'**
  String get statsArtists;

  /// No description provided for @statsSources.
  ///
  /// In en, this message translates to:
  /// **'Where you listen most'**
  String get statsSources;

  /// No description provided for @statsTopTracks.
  ///
  /// In en, this message translates to:
  /// **'Top tracks'**
  String get statsTopTracks;

  /// No description provided for @statsActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get statsActivity;

  /// No description provided for @statsTopArtists.
  ///
  /// In en, this message translates to:
  /// **'Top artists'**
  String get statsTopArtists;

  /// No description provided for @statsLocalFiles.
  ///
  /// In en, this message translates to:
  /// **'Local files'**
  String get statsLocalFiles;

  /// No description provided for @statsNoDataYet.
  ///
  /// In en, this message translates to:
  /// **'No data yet'**
  String get statsNoDataYet;

  /// No description provided for @statsFootnote.
  ///
  /// In en, this message translates to:
  /// **'Counted from the listening history on this device'**
  String get statsFootnote;

  /// No description provided for @statsCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get statsCopy;

  /// No description provided for @statsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get statsClear;

  /// No description provided for @statsClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sure? Tap again'**
  String get statsClearConfirm;

  /// No description provided for @statsCopied.
  ///
  /// In en, this message translates to:
  /// **'Statistics copied'**
  String get statsCopied;

  /// No description provided for @statsCleared.
  ///
  /// In en, this message translates to:
  /// **'Statistics cleared'**
  String get statsCleared;

  /// No description provided for @statsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get statsToday;

  /// No description provided for @statsPeriod7d.
  ///
  /// In en, this message translates to:
  /// **'7d'**
  String get statsPeriod7d;

  /// No description provided for @statsPeriod30d.
  ///
  /// In en, this message translates to:
  /// **'30d'**
  String get statsPeriod30d;

  /// No description provided for @statsPeriodAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get statsPeriodAll;

  /// No description provided for @statsLess.
  ///
  /// In en, this message translates to:
  /// **'less'**
  String get statsLess;

  /// No description provided for @statsMore.
  ///
  /// In en, this message translates to:
  /// **'more'**
  String get statsMore;

  /// No description provided for @statsZeroMinutes.
  ///
  /// In en, this message translates to:
  /// **'0 min'**
  String get statsZeroMinutes;

  /// No description provided for @statsHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String statsHoursMinutes(int hours, int minutes);

  /// No description provided for @statsMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String statsMinutes(int minutes);

  /// No description provided for @statsShareTitle.
  ///
  /// In en, this message translates to:
  /// **'🎵 My Bloom stats'**
  String get statsShareTitle;

  /// No description provided for @statsShareTracks.
  ///
  /// In en, this message translates to:
  /// **'📚 Tracks: {count}'**
  String statsShareTracks(int count);

  /// No description provided for @statsShareUnique.
  ///
  /// In en, this message translates to:
  /// **'🎵 Unique: {count}'**
  String statsShareUnique(int count);

  /// No description provided for @statsSharePlays.
  ///
  /// In en, this message translates to:
  /// **'▶️ Played: {count}'**
  String statsSharePlays(int count);

  /// No description provided for @statsShareTime.
  ///
  /// In en, this message translates to:
  /// **'🎧 Listening time: {value}'**
  String statsShareTime(String value);

  /// No description provided for @statsShareAvgLength.
  ///
  /// In en, this message translates to:
  /// **'📏 Average length: {value}'**
  String statsShareAvgLength(String value);

  /// No description provided for @statsShareAppTime.
  ///
  /// In en, this message translates to:
  /// **'⏱️ Time in app: {value}'**
  String statsShareAppTime(String value);

  /// No description provided for @statsShareFavArtist.
  ///
  /// In en, this message translates to:
  /// **'⭐ Favorite artist: {name}'**
  String statsShareFavArtist(String name);

  /// No description provided for @statsShareRecordDay.
  ///
  /// In en, this message translates to:
  /// **'🏆 Day record: {count}'**
  String statsShareRecordDay(int count);

  /// No description provided for @statsShareAvgPerDay.
  ///
  /// In en, this message translates to:
  /// **'📈 Daily average:'**
  String get statsShareAvgPerDay;

  /// No description provided for @statsShareSources.
  ///
  /// In en, this message translates to:
  /// **'📡 Where you listened most:'**
  String get statsShareSources;

  /// No description provided for @statsShareTopTracks.
  ///
  /// In en, this message translates to:
  /// **'🔥 Top tracks:'**
  String get statsShareTopTracks;

  /// No description provided for @statsShareTopArtists.
  ///
  /// In en, this message translates to:
  /// **'👤 Top artists:'**
  String get statsShareTopArtists;

  /// desktop: settings.nav.group.main
  ///
  /// In en, this message translates to:
  /// **'GENERAL'**
  String get setGroupMain;

  /// desktop: settings.nav.group.appearance
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE'**
  String get setGroupAppearance;

  /// desktop: settings.nav.group.integrations
  ///
  /// In en, this message translates to:
  /// **'INTEGRATIONS'**
  String get setGroupIntegrations;

  /// desktop: settings.nav.system
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get setSystem;

  /// desktop: settings.nav.audio
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get setAudio;

  /// No description provided for @setSwipes.
  ///
  /// In en, this message translates to:
  /// **'Swipes'**
  String get setSwipes;

  /// desktop: settings.nav.storage
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get setStorage;

  /// desktop: settings.nav.player
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get setPlayer;

  /// desktop: settings.nav.interface
  ///
  /// In en, this message translates to:
  /// **'Interface'**
  String get setInterface;

  /// desktop: settings.nav.customization
  ///
  /// In en, this message translates to:
  /// **'Customization'**
  String get setCustomization;

  /// No description provided for @setStub.
  ///
  /// In en, this message translates to:
  /// **'“{title}” isn’t built yet'**
  String setStub(String title);

  /// desktop: settings.view.titleAlign — the group holding it
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get pvGroupTitle;

  /// desktop: settings.view.titleAlign
  ///
  /// In en, this message translates to:
  /// **'Title alignment'**
  String get pvTitleAlign;

  /// No description provided for @pvTitleAlignLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get pvTitleAlignLeft;

  /// No description provided for @pvTitleAlignLeftSub.
  ///
  /// In en, this message translates to:
  /// **'title on the left'**
  String get pvTitleAlignLeftSub;

  /// No description provided for @pvTitleAlignCenter.
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get pvTitleAlignCenter;

  /// No description provided for @pvTitleAlignCenterSub.
  ///
  /// In en, this message translates to:
  /// **'title centered'**
  String get pvTitleAlignCenterSub;

  /// No description provided for @pvTitleAlignRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get pvTitleAlignRight;

  /// No description provided for @pvTitleAlignRightSub.
  ///
  /// In en, this message translates to:
  /// **'title on the right'**
  String get pvTitleAlignRightSub;

  /// the group holding the player style row
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get pvGroupLook;

  /// desktop: settings.view.style
  ///
  /// In en, this message translates to:
  /// **'Player style'**
  String get pvStyleRow;

  /// desktop: settings.view.style.standard
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get pvStyleStandard;

  /// No description provided for @pvStyleStandardSub.
  ///
  /// In en, this message translates to:
  /// **'the classic look with a square cover'**
  String get pvStyleStandardSub;

  /// desktop: settings.view.style.vinyl
  ///
  /// In en, this message translates to:
  /// **'Vinyl'**
  String get pvStyleVinyl;

  /// No description provided for @pvStyleVinylSub.
  ///
  /// In en, this message translates to:
  /// **'a spinning vinyl record'**
  String get pvStyleVinylSub;

  /// the group holding the slider type row
  ///
  /// In en, this message translates to:
  /// **'Slider'**
  String get pvGroupSlider;

  /// desktop: settings.view.slider
  ///
  /// In en, this message translates to:
  /// **'Slider type'**
  String get pvSliderRow;

  /// desktop: settings.view.slider.desc
  ///
  /// In en, this message translates to:
  /// **'style of the progress bar'**
  String get pvSliderSub;

  /// desktop: settings.view.slider.default
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get pvSliderStandard;

  /// desktop: settings.view.slider.thin
  ///
  /// In en, this message translates to:
  /// **'Thin'**
  String get pvSliderThin;

  /// desktop: settings.view.slider.wave
  ///
  /// In en, this message translates to:
  /// **'Wave'**
  String get pvSliderWave;

  /// desktop: settings.view.tab.anim
  ///
  /// In en, this message translates to:
  /// **'Track change'**
  String get pvGroupAnim;

  /// desktop: settings.view.trackAnim.player
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get pvAnimPlayer;

  /// No description provided for @pvAnimPlayerSub.
  ///
  /// In en, this message translates to:
  /// **'the full screen player — cover and title are configured separately'**
  String get pvAnimPlayerSub;

  /// desktop: settings.view.trackAnim.bar
  ///
  /// In en, this message translates to:
  /// **'Mini player'**
  String get pvAnimMini;

  /// No description provided for @pvAnimMiniSub.
  ///
  /// In en, this message translates to:
  /// **'the card above the tab bar'**
  String get pvAnimMiniSub;

  /// desktop: settings.view.trackAnim.cover
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get pvAnimCover;

  /// desktop: settings.view.trackAnim.text
  ///
  /// In en, this message translates to:
  /// **'Title and artist'**
  String get pvAnimText;

  /// No description provided for @pvAnimNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pvAnimNone;

  /// No description provided for @pvAnimSlide.
  ///
  /// In en, this message translates to:
  /// **'Slide'**
  String get pvAnimSlide;

  /// No description provided for @pvAnimFade.
  ///
  /// In en, this message translates to:
  /// **'Fade'**
  String get pvAnimFade;

  /// desktop: settings.view.lyrics
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get pvGroupLyrics;

  /// settings row that opens the lyrics style sheet
  ///
  /// In en, this message translates to:
  /// **'Style'**
  String get pvLyricsRow;

  /// No description provided for @pvLyricsMode.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get pvLyricsMode;

  /// No description provided for @pvLyricsModeSub.
  ///
  /// In en, this message translates to:
  /// **'where the cover goes once lyrics are on'**
  String get pvLyricsModeSub;

  /// No description provided for @pvLyricsModeOverlay.
  ///
  /// In en, this message translates to:
  /// **'Over the cover'**
  String get pvLyricsModeOverlay;

  /// No description provided for @pvLyricsModeReplace.
  ///
  /// In en, this message translates to:
  /// **'Instead of the cover'**
  String get pvLyricsModeReplace;

  /// desktop: settings.view.lyricsStyle.fill
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get pvLyricsFill;

  /// No description provided for @pvLyricsFillSub.
  ///
  /// In en, this message translates to:
  /// **'what measures progress along the line; granular fills need synced lyrics'**
  String get pvLyricsFillSub;

  /// No description provided for @pvLyricsFillLine.
  ///
  /// In en, this message translates to:
  /// **'By line'**
  String get pvLyricsFillLine;

  /// No description provided for @pvLyricsFillWord.
  ///
  /// In en, this message translates to:
  /// **'By word'**
  String get pvLyricsFillWord;

  /// No description provided for @pvLyricsFillLetter.
  ///
  /// In en, this message translates to:
  /// **'By letter'**
  String get pvLyricsFillLetter;

  /// No description provided for @pvLyricsFillWipe.
  ///
  /// In en, this message translates to:
  /// **'Smooth'**
  String get pvLyricsFillWipe;

  /// desktop: settings.view.lyricsStyle.fx
  ///
  /// In en, this message translates to:
  /// **'Effect'**
  String get pvLyricsFx;

  /// No description provided for @pvLyricsFxSub.
  ///
  /// In en, this message translates to:
  /// **'how the part being sung lights up'**
  String get pvLyricsFxSub;

  /// No description provided for @pvLyricsFxNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pvLyricsFxNone;

  /// No description provided for @pvLyricsFxFade.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get pvLyricsFxFade;

  /// No description provided for @pvLyricsFxGlow.
  ///
  /// In en, this message translates to:
  /// **'Glow'**
  String get pvLyricsFxGlow;

  /// No description provided for @pvLyricsFxSpring.
  ///
  /// In en, this message translates to:
  /// **'Spring'**
  String get pvLyricsFxSpring;

  /// desktop: settings.view.miniPlayer
  ///
  /// In en, this message translates to:
  /// **'Mini player'**
  String get pvGroupMini;

  /// desktop: settings.view.mpBg
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get pvMiniBgRow;

  /// No description provided for @pvMiniBgSub.
  ///
  /// In en, this message translates to:
  /// **'what fills the card above the tab bar'**
  String get pvMiniBgSub;

  /// No description provided for @pvMiniBgTheme.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get pvMiniBgTheme;

  /// No description provided for @pvMiniBgCoverColor.
  ///
  /// In en, this message translates to:
  /// **'Cover color'**
  String get pvMiniBgCoverColor;

  /// No description provided for @pvMiniBgCover.
  ///
  /// In en, this message translates to:
  /// **'The cover itself'**
  String get pvMiniBgCover;

  /// desktop: settings.view.mpProgress
  ///
  /// In en, this message translates to:
  /// **'Progress indicators'**
  String get pvMiniProgressRow;

  /// No description provided for @pvMiniProgressSub.
  ///
  /// In en, this message translates to:
  /// **'several can be on at once'**
  String get pvMiniProgressSub;

  /// No description provided for @pvMiniProgressNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pvMiniProgressNone;

  /// No description provided for @pvMiniProgressLine.
  ///
  /// In en, this message translates to:
  /// **'Line at the bottom'**
  String get pvMiniProgressLine;

  /// No description provided for @pvMiniProgressFill.
  ///
  /// In en, this message translates to:
  /// **'Background fill'**
  String get pvMiniProgressFill;

  /// No description provided for @pvMiniProgressRing.
  ///
  /// In en, this message translates to:
  /// **'Ring around the cover'**
  String get pvMiniProgressRing;

  /// desktop: settings.view.mpCoverShape
  ///
  /// In en, this message translates to:
  /// **'Cover shape'**
  String get pvMiniShapeRow;

  /// No description provided for @pvMiniShapeRounded.
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get pvMiniShapeRounded;

  /// No description provided for @pvMiniShapeCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle'**
  String get pvMiniShapeCircle;

  /// desktop: settings.view.mpRounded
  ///
  /// In en, this message translates to:
  /// **'Corner rounding'**
  String get pvMiniRadiusRow;

  /// No description provided for @pvMiniRadiusNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pvMiniRadiusNone;

  /// No description provided for @pvMiniRadiusSoft.
  ///
  /// In en, this message translates to:
  /// **'Soft'**
  String get pvMiniRadiusSoft;

  /// No description provided for @pvMiniRadiusRounded.
  ///
  /// In en, this message translates to:
  /// **'Rounded'**
  String get pvMiniRadiusRounded;

  /// No description provided for @pvMiniRadiusPill.
  ///
  /// In en, this message translates to:
  /// **'Pill'**
  String get pvMiniRadiusPill;

  /// desktop: settings.view.mpHide
  ///
  /// In en, this message translates to:
  /// **'Controls'**
  String get pvMiniButtonsRow;

  /// No description provided for @pvMiniButtonsSub.
  ///
  /// In en, this message translates to:
  /// **'what stands in the row right of the title'**
  String get pvMiniButtonsSub;

  /// No description provided for @pvMiniButtonsNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get pvMiniButtonsNone;

  /// No description provided for @pvMiniButtonPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get pvMiniButtonPrev;

  /// No description provided for @pvMiniButtonPlay.
  ///
  /// In en, this message translates to:
  /// **'Play/Pause'**
  String get pvMiniButtonPlay;

  /// No description provided for @pvMiniButtonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get pvMiniButtonNext;

  /// No description provided for @pvMiniButtonFav.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get pvMiniButtonFav;

  /// desktop: player.lyrics
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get playerLyrics;

  /// desktop: lyrics.loading
  ///
  /// In en, this message translates to:
  /// **'Loading lyrics…'**
  String get lyricsLoading;

  /// desktop: lyrics.notFound
  ///
  /// In en, this message translates to:
  /// **'Lyrics not found'**
  String get lyricsNotFound;

  /// No description provided for @swZoneLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get swZoneLibrary;

  /// No description provided for @swZoneQueue.
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get swZoneQueue;

  /// No description provided for @swZoneMini.
  ///
  /// In en, this message translates to:
  /// **'Mini player'**
  String get swZoneMini;

  /// No description provided for @swZonePlayer.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get swZonePlayer;

  /// No description provided for @swLeft.
  ///
  /// In en, this message translates to:
  /// **'Swipe left'**
  String get swLeft;

  /// No description provided for @swRight.
  ///
  /// In en, this message translates to:
  /// **'Swipe right'**
  String get swRight;

  /// No description provided for @swActNone.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get swActNone;

  /// No description provided for @swActLike.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get swActLike;

  /// No description provided for @swActQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get swActQueue;

  /// desktop: lib.ctx.playNext — insert right after the current track
  ///
  /// In en, this message translates to:
  /// **'Play next'**
  String get swActPlayNext;

  /// No description provided for @swActNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get swActNext;

  /// No description provided for @swActPrev.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get swActPrev;

  /// No description provided for @swActDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get swActDownload;

  /// No description provided for @swActDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get swActDelete;

  /// No description provided for @swAddedToQueue.
  ///
  /// In en, this message translates to:
  /// **'Added to queue'**
  String get swAddedToQueue;

  /// No description provided for @swAlreadyInQueue.
  ///
  /// In en, this message translates to:
  /// **'Already in the queue'**
  String get swAlreadyInQueue;

  /// No description provided for @swPlaysNext.
  ///
  /// In en, this message translates to:
  /// **'Plays next'**
  String get swPlaysNext;

  /// No description provided for @swLiked.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get swLiked;

  /// No description provided for @swUnliked.
  ///
  /// In en, this message translates to:
  /// **'Removed from favorites'**
  String get swUnliked;

  /// No description provided for @swRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get swRemoved;

  /// desktop: settings.interface.cat.language
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get apLanguage;

  /// No description provided for @apLanguageRu.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get apLanguageRu;

  /// No description provided for @apLanguageEn.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get apLanguageEn;

  /// desktop: settings.interface.cat.theme
  ///
  /// In en, this message translates to:
  /// **'THEME'**
  String get apTheme;

  /// row that opens the theme picker sheet
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get apThemeRow;

  /// desktop: theme.ownName — title of the theme creator sheet
  ///
  /// In en, this message translates to:
  /// **'Custom theme'**
  String get thNew;

  /// desktop: theme.defaultName
  ///
  /// In en, this message translates to:
  /// **'My theme'**
  String get thNameDefault;

  /// desktop: theme.slot.bg
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get thSlotBg;

  /// desktop: theme.slot.card
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get thSlotCard;

  /// desktop: theme.slot.accent
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get thSlotAccent;

  /// desktop: theme.random
  ///
  /// In en, this message translates to:
  /// **'Random colors'**
  String get thRandom;

  /// desktop: theme.toast.created
  ///
  /// In en, this message translates to:
  /// **'Theme “{name}” created'**
  String thCreated(String name);

  /// desktop: theme.toast.deleted
  ///
  /// In en, this message translates to:
  /// **'Preset deleted'**
  String get thDeleted;

  /// desktop: settings.interface.autoAccent.title
  ///
  /// In en, this message translates to:
  /// **'Auto accent'**
  String get apAutoAccent;

  /// desktop: settings.interface.autoAccent.sub
  ///
  /// In en, this message translates to:
  /// **'Accent color from the track cover'**
  String get apAutoAccentSub;

  /// desktop: settings.interface.autoAccent.level
  ///
  /// In en, this message translates to:
  /// **'Accent brightness'**
  String get apAutoAccentLevel;

  /// desktop: settings.interface.cat.interface
  ///
  /// In en, this message translates to:
  /// **'CORNERS'**
  String get apCorners;

  /// No description provided for @apPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'A block looks like this'**
  String get apPreviewTitle;

  /// No description provided for @apPreviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'and secondary text'**
  String get apPreviewSubtitle;

  /// desktop: settings.interface.accentBadges.title
  ///
  /// In en, this message translates to:
  /// **'Badges in accent color'**
  String get apBadgesTitle;

  /// desktop: settings.interface.accentBadges.sub
  ///
  /// In en, this message translates to:
  /// **'Source badges use their brand colors by default; enable to tint them with the accent'**
  String get apBadgesSubtitle;

  /// phone only: the desktop app navigates from a sidebar
  ///
  /// In en, this message translates to:
  /// **'TAB BAR'**
  String get apNavBar;

  /// No description provided for @apNavBarRow.
  ///
  /// In en, this message translates to:
  /// **'Tab bar'**
  String get apNavBarRow;

  /// No description provided for @apNavBarPlain.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get apNavBarPlain;

  /// No description provided for @apNavBarRounded.
  ///
  /// In en, this message translates to:
  /// **'Rounded top'**
  String get apNavBarRounded;

  /// No description provided for @apNavBarDome.
  ///
  /// In en, this message translates to:
  /// **'Dome'**
  String get apNavBarDome;

  /// No description provided for @apNavBarFloating.
  ///
  /// In en, this message translates to:
  /// **'Floating'**
  String get apNavBarFloating;

  /// No description provided for @apNavBarPill.
  ///
  /// In en, this message translates to:
  /// **'Pill'**
  String get apNavBarPill;

  /// No description provided for @scHelp.
  ///
  /// In en, this message translates to:
  /// **'Usually not needed: the key is picked up automatically — by scraping the site, and failing that by trying known ones. Setting your own makes sense if SoundCloud stopped responding.'**
  String get scHelp;

  /// No description provided for @scHint.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get scHint;

  /// No description provided for @scCheckConnection.
  ///
  /// In en, this message translates to:
  /// **'Check connection'**
  String get scCheckConnection;

  /// No description provided for @scConnectionOk.
  ///
  /// In en, this message translates to:
  /// **'Connection works'**
  String get scConnectionOk;

  /// No description provided for @scConnectionFail.
  ///
  /// In en, this message translates to:
  /// **'Not responding'**
  String get scConnectionFail;

  /// No description provided for @scActiveKey.
  ///
  /// In en, this message translates to:
  /// **'Active key'**
  String get scActiveKey;

  /// No description provided for @scSetup.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get scSetup;

  /// No description provided for @scReconfigure.
  ///
  /// In en, this message translates to:
  /// **'Reconfigure'**
  String get scReconfigure;

  /// No description provided for @scStatusAuto.
  ///
  /// In en, this message translates to:
  /// **'The key is picked up automatically'**
  String get scStatusAuto;

  /// No description provided for @scStatusManual.
  ///
  /// In en, this message translates to:
  /// **'Running on your own client_id'**
  String get scStatusManual;

  /// desktop: settings.sc.help.title
  ///
  /// In en, this message translates to:
  /// **'How to get a client_id'**
  String get scGuideTitle;

  /// No description provided for @scGuideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Step-by-step guide — usually not needed'**
  String get scGuideSubtitle;

  /// desktop: settings.sc.step1.* (**bold** marks what to look for)
  ///
  /// In en, this message translates to:
  /// **'Open **soundcloud.com** in a desktop browser'**
  String get scStep1;

  /// No description provided for @scStep2.
  ///
  /// In en, this message translates to:
  /// **'Press **F12** → the **Network** tab'**
  String get scStep2;

  /// No description provided for @scStep3.
  ///
  /// In en, this message translates to:
  /// **'Press play on any track'**
  String get scStep3;

  /// No description provided for @scStep4.
  ///
  /// In en, this message translates to:
  /// **'Find the request to **api-v2.soundcloud.com**'**
  String get scStep4;

  /// No description provided for @scStep5.
  ///
  /// In en, this message translates to:
  /// **'Copy the **client_id** parameter from the URL'**
  String get scStep5;

  /// desktop: settings.ym.checking
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get ymChecking;

  /// desktop: settings.ym.connected
  ///
  /// In en, this message translates to:
  /// **'✓ Connected'**
  String get ymConnected;

  /// desktop: settings.ym.notConnected
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get ymNotConnected;

  /// desktop: settings.ym.logout
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get ymLogout;

  /// desktop: settings.ym.plus.active.a
  ///
  /// In en, this message translates to:
  /// **'Yandex Plus active'**
  String get ymPlusActiveA;

  /// desktop: settings.ym.plus.active.b
  ///
  /// In en, this message translates to:
  /// **'— tracks play directly from Yandex.'**
  String get ymPlusActiveB;

  /// desktop: settings.ym.plus.none.a
  ///
  /// In en, this message translates to:
  /// **'No Plus'**
  String get ymPlusNoneA;

  /// desktop: settings.ym.plus.none.b
  ///
  /// In en, this message translates to:
  /// **'— some tracks may be unavailable for playback.'**
  String get ymPlusNoneB;

  /// desktop: settings.ym.plus.unknown
  ///
  /// In en, this message translates to:
  /// **'Subscription status unknown.'**
  String get ymPlusUnknown;

  /// desktop: settings.ym.loginHint
  ///
  /// In en, this message translates to:
  /// **'Sign in with your Yandex ID. A confirmation page will open — enter the code there.'**
  String get ymLoginHint;

  /// desktop: settings.ym.connect
  ///
  /// In en, this message translates to:
  /// **'Connect Yandex Music'**
  String get ymConnect;

  /// desktop: settings.ym.codePrompt.a
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get ymCodePromptA;

  /// desktop: settings.ym.codePrompt.b
  ///
  /// In en, this message translates to:
  /// **'and enter the code:'**
  String get ymCodePromptB;

  /// No description provided for @ymOpenPage.
  ///
  /// In en, this message translates to:
  /// **'Open the page'**
  String get ymOpenPage;

  /// No description provided for @ymCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get ymCodeCopied;

  /// desktop: ym.auth.gettingCode
  ///
  /// In en, this message translates to:
  /// **'Getting code…'**
  String get ymGettingCode;

  /// desktop: ym.auth.waiting
  ///
  /// In en, this message translates to:
  /// **'Waiting for confirmation…'**
  String get ymWaiting;

  /// desktop: ym.auth.codeExpired
  ///
  /// In en, this message translates to:
  /// **'Code expired — press “Connect” again.'**
  String get ymCodeExpired;

  /// No description provided for @ymErrAuth.
  ///
  /// In en, this message translates to:
  /// **'Yandex Music token is invalid — sign in again'**
  String get ymErrAuth;

  /// No description provided for @ymErrNeedPlus.
  ///
  /// In en, this message translates to:
  /// **'Track unavailable — Yandex Plus subscription required'**
  String get ymErrNeedPlus;

  /// No description provided for @ymErrNetwork.
  ///
  /// In en, this message translates to:
  /// **'Yandex is not responding'**
  String get ymErrNetwork;

  /// No description provided for @ymGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'How to connect Yandex Music'**
  String get ymGuideTitle;

  /// No description provided for @ymGuideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Yandex ID — four steps'**
  String get ymGuideSubtitle;

  /// No description provided for @ymStep1.
  ///
  /// In en, this message translates to:
  /// **'Press **Connect Yandex Music**'**
  String get ymStep1;

  /// No description provided for @ymStep2.
  ///
  /// In en, this message translates to:
  /// **'The **ya.ru/device** page opens — sign in to your account'**
  String get ymStep2;

  /// No description provided for @ymStep3.
  ///
  /// In en, this message translates to:
  /// **'Enter the code Bloom shows (tap the code to copy it)'**
  String get ymStep3;

  /// No description provided for @ymStep4.
  ///
  /// In en, this message translates to:
  /// **'Come back to the app — the connection is picked up on its own'**
  String get ymStep4;

  /// No description provided for @ymGuideNote.
  ///
  /// In en, this message translates to:
  /// **'Without a Yandex Plus subscription some tracks won\'t play — those can be listened to from other platforms.'**
  String get ymGuideNote;

  /// desktop: settings.ytm.status
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get ytmConfigured;

  /// desktop: settings.ytm.noAuth
  ///
  /// In en, this message translates to:
  /// **'No authentication needed for now'**
  String get ytmNoAuth;

  /// desktop: settings.ytm.help (без запасного пути через SoundCloud — в мобилке бриджа нет)
  ///
  /// In en, this message translates to:
  /// **'Search, pages and link import work without auth. Playback and downloads come straight from YouTube.'**
  String get ytmHelp;

  /// No description provided for @ytmGuideTitle.
  ///
  /// In en, this message translates to:
  /// **'What already works'**
  String get ytmGuideTitle;

  /// No description provided for @ytmGuideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing to connect'**
  String get ytmGuideSubtitle;

  /// No description provided for @ytmStep1.
  ///
  /// In en, this message translates to:
  /// **'Search, artist, album and playlist pages — **no sign-in**'**
  String get ytmStep1;

  /// No description provided for @ytmStep2.
  ///
  /// In en, this message translates to:
  /// **'Link import: paste an album or playlist link in the **Library**'**
  String get ytmStep2;

  /// No description provided for @ytmStep3.
  ///
  /// In en, this message translates to:
  /// **'Playback and downloads come straight from **YouTube**'**
  String get ytmStep3;

  /// desktop: settings.storage.offline
  ///
  /// In en, this message translates to:
  /// **'Offline track cache'**
  String get stOfflineCache;

  /// desktop: settings.storage.lyrics
  ///
  /// In en, this message translates to:
  /// **'Lyrics'**
  String get stLyrics;

  /// desktop: settings.storage.customization
  ///
  /// In en, this message translates to:
  /// **'Customization'**
  String get stCustom;

  /// No description provided for @stCounting.
  ///
  /// In en, this message translates to:
  /// **'Counting…'**
  String get stCounting;

  /// desktop: settings.storage.used
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get stUsed;

  /// desktop: settings.storage.manage
  ///
  /// In en, this message translates to:
  /// **'Clear data'**
  String get stManage;

  /// No description provided for @stFiles.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} file} other{{count} files}}'**
  String stFiles(int count);

  /// desktop: settings.storage.of
  ///
  /// In en, this message translates to:
  /// **'{percent}% of {total}'**
  String stUsedOf(String percent, String total);

  /// No description provided for @stClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get stClearAll;

  /// No description provided for @stClearBody.
  ///
  /// In en, this message translates to:
  /// **'The downloaded copies will be deleted and those tracks will stop playing without a network. They stay in your library and playlists.'**
  String get stClearBody;

  /// No description provided for @stClearLyricsBody.
  ///
  /// In en, this message translates to:
  /// **'The saved lyrics will be deleted — they are fetched again on the next playback.'**
  String get stClearLyricsBody;

  /// No description provided for @stClearCustomBody.
  ///
  /// In en, this message translates to:
  /// **'All uploaded images will be deleted. If one is currently set as a background or a cover, it will be reset.'**
  String get stClearCustomBody;

  /// No description provided for @stClearAllBody.
  ///
  /// In en, this message translates to:
  /// **'The caches — offline copies, lyrics and images — will be deleted. Your library and playlists are not affected.'**
  String get stClearAllBody;

  /// No description provided for @stCleared.
  ///
  /// In en, this message translates to:
  /// **'Offline cache cleared, files deleted: {count}'**
  String stCleared(int count);

  /// No description provided for @stLyricsCleared.
  ///
  /// In en, this message translates to:
  /// **'Lyrics cache cleared'**
  String get stLyricsCleared;

  /// No description provided for @stCustomCleared.
  ///
  /// In en, this message translates to:
  /// **'Customization library cleared'**
  String get stCustomCleared;

  /// No description provided for @stAllCleared.
  ///
  /// In en, this message translates to:
  /// **'App data cleared'**
  String get stAllCleared;

  /// No description provided for @stBytes.
  ///
  /// In en, this message translates to:
  /// **'{value} B'**
  String stBytes(String value);

  /// No description provided for @stKilobytes.
  ///
  /// In en, this message translates to:
  /// **'{value} KB'**
  String stKilobytes(String value);

  /// No description provided for @stMegabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} MB'**
  String stMegabytes(String value);

  /// No description provided for @stGigabytes.
  ///
  /// In en, this message translates to:
  /// **'{value} GB'**
  String stGigabytes(String value);

  /// desktop: settings.library.import.title, narrowed: the phone has no watched folders, only single files
  ///
  /// In en, this message translates to:
  /// **'Your own tracks'**
  String get ltImportTitle;

  /// desktop: settings.library.import.desc
  ///
  /// In en, this message translates to:
  /// **'What Bloom does with a file you add with + in All tracks. Tracks already added stay as they are.'**
  String get ltImportDesc;

  /// desktop: settings.library.import.inPlace
  ///
  /// In en, this message translates to:
  /// **'In place'**
  String get ltImportInPlace;

  /// desktop: settings.library.import.inPlaceTip
  ///
  /// In en, this message translates to:
  /// **'The file stays where it is and takes no extra space. Delete or move it and the track stops playing.'**
  String get ltImportInPlaceTip;

  /// desktop: settings.library.import.copy
  ///
  /// In en, this message translates to:
  /// **'Into Bloom'**
  String get ltImportCopy;

  /// desktop: settings.library.import.copyTip
  ///
  /// In en, this message translates to:
  /// **'Bloom copies the file into itself. The track plays even if the original is gone, but the space is used twice.'**
  String get ltImportCopyTip;

  /// No description provided for @ltAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Added {count} track} other{Added {count} tracks}}'**
  String ltAdded(int count);

  /// desktop: lib.import.nothingAdded
  ///
  /// In en, this message translates to:
  /// **'Nothing to add: these tracks are already in the library, or the format is unsupported'**
  String get ltNothingAdded;

  /// phone only: the desktop opens a native dialog from Rust and cannot fail this way
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker'**
  String get ltImportFailed;

  /// phone only: shown in the player when a content:// grant is gone or the copy was wiped
  ///
  /// In en, this message translates to:
  /// **'File is not available'**
  String get ltFileGone;

  /// No description provided for @custLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get custLibrary;

  /// No description provided for @custPresets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get custPresets;

  /// No description provided for @custAddUrl.
  ///
  /// In en, this message translates to:
  /// **'Add by URL'**
  String get custAddUrl;

  /// No description provided for @custUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get custUpload;

  /// No description provided for @custLibraryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Library is empty — add a photo or GIF'**
  String get custLibraryEmpty;

  /// No description provided for @custAdded.
  ///
  /// In en, this message translates to:
  /// **'Added!'**
  String get custAdded;

  /// No description provided for @custBadUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid image URL'**
  String get custBadUrl;

  /// No description provided for @custFilesAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} file added} other{{count} files added}}'**
  String custFilesAdded(int count);

  /// No description provided for @custCtxBg.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get custCtxBg;

  /// No description provided for @custCtxCover.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get custCtxCover;

  /// No description provided for @custCtxSlider.
  ///
  /// In en, this message translates to:
  /// **'Slider'**
  String get custCtxSlider;

  /// No description provided for @custBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get custBlur;

  /// No description provided for @custDim.
  ///
  /// In en, this message translates to:
  /// **'Dim'**
  String get custDim;

  /// No description provided for @custImageGone.
  ///
  /// In en, this message translates to:
  /// **'Image unavailable'**
  String get custImageGone;

  /// No description provided for @custOnlyForBg.
  ///
  /// In en, this message translates to:
  /// **'Background only'**
  String get custOnlyForBg;

  /// No description provided for @custPresetCreate.
  ///
  /// In en, this message translates to:
  /// **'Create preset'**
  String get custPresetCreate;

  /// No description provided for @custImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get custImport;

  /// No description provided for @custPresetsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Save the current settings as a preset'**
  String get custPresetsEmpty;

  /// No description provided for @custPresetNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name the preset...'**
  String get custPresetNameHint;

  /// No description provided for @custPresetSaved.
  ///
  /// In en, this message translates to:
  /// **'Preset “{name}” saved!'**
  String custPresetSaved(String name);

  /// No description provided for @custPresetNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing is applied — set a background, cover or slider first'**
  String get custPresetNothing;

  /// No description provided for @custPresetsFull.
  ///
  /// In en, this message translates to:
  /// **'No room for more presets — the limit is {limit}'**
  String custPresetsFull(int limit);

  /// No description provided for @custPresetUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get custPresetUntitled;

  /// No description provided for @custPresetSlots.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} image} other{{count} images}}'**
  String custPresetSlots(int count);

  /// No description provided for @custPresetApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get custPresetApply;

  /// No description provided for @custPresetExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get custPresetExport;

  /// No description provided for @custPresetApplied.
  ///
  /// In en, this message translates to:
  /// **'Preset “{name}” applied'**
  String custPresetApplied(String name);

  /// No description provided for @custPresetExported.
  ///
  /// In en, this message translates to:
  /// **'Preset saved to file'**
  String get custPresetExported;

  /// No description provided for @custImportBad.
  ///
  /// In en, this message translates to:
  /// **'Could not read file — invalid format'**
  String get custImportBad;

  /// No description provided for @custImported.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} preset imported} other{{count} presets imported}}'**
  String custImported(int count);

  /// No description provided for @apCoverAsBg.
  ///
  /// In en, this message translates to:
  /// **'Track cover as background'**
  String get apCoverAsBg;

  /// No description provided for @apCoverAsBgSub.
  ///
  /// In en, this message translates to:
  /// **'Use the current track cover as the app background'**
  String get apCoverAsBgSub;

  /// desktop: settings.interface.cat.transparency
  ///
  /// In en, this message translates to:
  /// **'TRANSPARENCY'**
  String get apTrGroup;

  /// desktop: settings.interface.transparency.title
  ///
  /// In en, this message translates to:
  /// **'Transparency'**
  String get apTrTitle;

  /// Subtitle of the master switch: the level the blocks are set to
  ///
  /// In en, this message translates to:
  /// **'On ({percent}%)'**
  String apTrOn(int percent);

  /// desktop: settings.interface.transparency.off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get apTrOff;

  /// desktop: settings.interface.transparency.blockOpacity, inverted — here it is how much shows through
  ///
  /// In en, this message translates to:
  /// **'Transparency level'**
  String get apTrLevel;

  /// desktop: settings.interface.transparency.glassStr
  ///
  /// In en, this message translates to:
  /// **'Glass brightness'**
  String get apTrBrightness;

  /// desktop: settings.interface.transparency.glassBlur
  ///
  /// In en, this message translates to:
  /// **'Glass blur'**
  String get apTrBlur;

  /// desktop: settings.interface.transparency.overlays.title
  ///
  /// In en, this message translates to:
  /// **'Overlay transparency'**
  String get apTrOverlays;

  /// desktop: settings.interface.transparency.overlays.sub — no side panels or context menus on the phone
  ///
  /// In en, this message translates to:
  /// **'Glass for sheets, menus and dialogs'**
  String get apTrOverlaysSub;

  /// desktop: onb.tagline
  ///
  /// In en, this message translates to:
  /// **'your personal player'**
  String get onbTagline;

  /// desktop: onb.hello.sub
  ///
  /// In en, this message translates to:
  /// **'A few quick steps and the player is yours'**
  String get onbHelloSub;

  /// desktop: onb.hello.cta
  ///
  /// In en, this message translates to:
  /// **'Let\'s go'**
  String get onbHelloCta;

  /// desktop: onb.next
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onbNext;

  /// desktop: onb.back
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get onbBack;

  /// desktop: onb.done
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get onbDone;

  /// desktop: onb.profile.title
  ///
  /// In en, this message translates to:
  /// **'Tell us about yourself'**
  String get onbProfileTitle;

  /// desktop: onb.profile.sub
  ///
  /// In en, this message translates to:
  /// **'Avatar, cover and name. You can change all of it later in your profile.'**
  String get onbProfileSub;

  /// desktop: onb.addCover
  ///
  /// In en, this message translates to:
  /// **'Add profile cover'**
  String get onbAddCover;

  /// desktop: onb.theme.title
  ///
  /// In en, this message translates to:
  /// **'Pick a look'**
  String get onbThemeTitle;

  /// desktop: onb.theme.sub
  ///
  /// In en, this message translates to:
  /// **'The theme applies instantly — see how it feels.'**
  String get onbThemeSub;

  /// desktop: onb.theme.hint
  ///
  /// In en, this message translates to:
  /// **'More themes live in settings'**
  String get onbThemeHint;

  /// desktop: onb.library.title
  ///
  /// In en, this message translates to:
  /// **'Connect your music'**
  String get onbMusicTitle;

  /// desktop: onb.library.sub, rewritten: there are no local folders on the phone
  ///
  /// In en, this message translates to:
  /// **'Sign in to your platforms — their tracks show up in search right away.'**
  String get onbMusicSub;

  /// desktop: onb.music.platforms
  ///
  /// In en, this message translates to:
  /// **'PLATFORMS'**
  String get onbMusicPlatforms;

  /// desktop: onb.library.skip
  ///
  /// In en, this message translates to:
  /// **'None of this is required — it all lives in settings'**
  String get onbMusicSkip;

  /// desktop: onb.plat.connected
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get onbPlatConnected;

  /// desktop: onb.plat.notConnected
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get onbPlatNotConnected;

  /// desktop: onb.plat.autoCheck
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get onbPlatCheck;

  /// desktop: onb.welcome
  ///
  /// In en, this message translates to:
  /// **'Hi, {name}!'**
  String onbWelcome(String name);

  /// desktop: onb.welcomeSub
  ///
  /// In en, this message translates to:
  /// **'Welcome to Bloom'**
  String get onbWelcomeSub;

  /// debug builds only: the desktop has showOnboarding() in the console
  ///
  /// In en, this message translates to:
  /// **'Show onboarding again'**
  String get onbReplay;

  /// desktop: wave.title
  ///
  /// In en, this message translates to:
  /// **'My Wave'**
  String get waveTitle;

  /// desktop: wave.start
  ///
  /// In en, this message translates to:
  /// **'Start My Wave'**
  String get waveStart;

  /// desktop: wave.stop, phrased as a menu item
  ///
  /// In en, this message translates to:
  /// **'Stop the wave'**
  String get waveStop;

  /// desktop: wave.label.track
  ///
  /// In en, this message translates to:
  /// **'Track wave'**
  String get waveLabelTrack;

  /// desktop: wave.label.queue
  ///
  /// In en, this message translates to:
  /// **'Similar to queue'**
  String get waveLabelQueue;

  /// desktop: wave.label.artist
  ///
  /// In en, this message translates to:
  /// **'Artist wave'**
  String get waveLabelArtist;

  /// track menu item; desktop: wave.startFrom takes the name, here the menu already stands on the track
  ///
  /// In en, this message translates to:
  /// **'Wave from this track'**
  String get waveFromTrack;

  /// queue screen action; desktop: wave.label.queue
  ///
  /// In en, this message translates to:
  /// **'Similar to queue'**
  String get waveFromQueue;

  /// artist page action; desktop: wave.label.artist
  ///
  /// In en, this message translates to:
  /// **'Artist wave'**
  String get waveFromArtist;

  /// desktop: wave.tune
  ///
  /// In en, this message translates to:
  /// **'Customize'**
  String get waveTune;

  /// desktop: wave.dislikes
  ///
  /// In en, this message translates to:
  /// **'Dislikes'**
  String get waveDislikes;

  /// desktop: wave.dislikesTitle
  ///
  /// In en, this message translates to:
  /// **'Wave dislikes'**
  String get waveDislikesTitle;

  /// desktop: wave.noDislikes
  ///
  /// In en, this message translates to:
  /// **'Nothing disliked yet'**
  String get waveNoDislikes;

  /// desktop: wave.dislike
  ///
  /// In en, this message translates to:
  /// **'Dislike'**
  String get waveDislike;

  /// desktop: wave.unlike
  ///
  /// In en, this message translates to:
  /// **'Remove dislike'**
  String get waveUndislike;

  /// desktop: wave.toast.added
  ///
  /// In en, this message translates to:
  /// **'Disliked — won’t suggest it in the wave again'**
  String get waveToastDisliked;

  /// desktop: wave.toast.removed
  ///
  /// In en, this message translates to:
  /// **'Dislike removed'**
  String get waveToastUndisliked;

  /// desktop: wave.toast.stopped
  ///
  /// In en, this message translates to:
  /// **'Wave stopped'**
  String get waveToastStopped;

  /// desktop: wave.toast.notEnough
  ///
  /// In en, this message translates to:
  /// **'Not enough data for My Wave — listen to some music first'**
  String get waveToastNotEnough;

  /// desktop: wave.toast.noSeed
  ///
  /// In en, this message translates to:
  /// **'Couldn’t find a track for the wave'**
  String get waveToastNoSeed;

  /// desktop: wave.toast.scOnly, extended: the phone has the Yandex station too
  ///
  /// In en, this message translates to:
  /// **'The wave only works for SoundCloud and Yandex tracks'**
  String get waveToastScOnly;

  /// desktop: wave.toast.queueEmpty
  ///
  /// In en, this message translates to:
  /// **'Queue is empty'**
  String get waveToastQueueEmpty;

  /// desktop: wave.toast.noScInQueue
  ///
  /// In en, this message translates to:
  /// **'No SoundCloud tracks in the queue to find similar ones'**
  String get waveToastNoScInQueue;

  /// desktop: wave.toast.artistNoSeeds
  ///
  /// In en, this message translates to:
  /// **'No tracks of this artist to build a wave from'**
  String get waveToastArtistNoSeeds;

  /// desktop: wave.toast.noSimilar
  ///
  /// In en, this message translates to:
  /// **'SoundCloud returned no similar tracks'**
  String get waveToastNoSimilar;

  /// desktop: wave.toast.ymNoAuth
  ///
  /// In en, this message translates to:
  /// **'Not signed in to Yandex Music (Settings → Platforms)'**
  String get waveToastYmNoAuth;

  /// desktop: wave.toast.ymEmpty
  ///
  /// In en, this message translates to:
  /// **'The Yandex wave is empty'**
  String get waveToastYmEmpty;

  /// desktop: wave.toast.ymError, without the raw API message
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach the Yandex wave'**
  String get waveToastYmFailed;

  /// desktop: settings.lastfm.connectedAs, without the ✓ — the page shows it in green
  ///
  /// In en, this message translates to:
  /// **'Connected as {user}'**
  String lfmConnectedAs(String user);

  /// desktop: settings.lastfm.notConnected
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get lfmNotConnected;

  /// desktop: settings.lastfm.login
  ///
  /// In en, this message translates to:
  /// **'Sign in with Last.fm'**
  String get lfmLogin;

  /// desktop: settings.lastfm.done
  ///
  /// In en, this message translates to:
  /// **'Done — I confirmed'**
  String get lfmDone;

  /// desktop: settings.lastfm.logout
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get lfmLogout;

  /// phone only: button that opens the key form (on desktop it lives under the “?” popup)
  ///
  /// In en, this message translates to:
  /// **'API keys'**
  String get lfmKeys;

  /// desktop: settings.lastfm.saveKeys
  ///
  /// In en, this message translates to:
  /// **'Save keys'**
  String get lfmSaveKeys;

  /// desktop: settings.lastfm.scrobble
  ///
  /// In en, this message translates to:
  /// **'Scrobbling'**
  String get lfmScrobble;

  /// desktop: settings.lastfm.scrobble.sub
  ///
  /// In en, this message translates to:
  /// **'Count listened tracks on Last.fm'**
  String get lfmScrobbleSub;

  /// desktop: settings.lastfm.nowPlaying.sub
  ///
  /// In en, this message translates to:
  /// **'Update the “Now Playing” status'**
  String get lfmNowPlayingSub;

  /// phone only: the guide sheet, built from the desktop “?” popup
  ///
  /// In en, this message translates to:
  /// **'How to connect Last.fm'**
  String get lfmGuideTitle;

  /// No description provided for @lfmGuideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your own app key and a browser sign-in'**
  String get lfmGuideSubtitle;

  /// No description provided for @lfmStep1.
  ///
  /// In en, this message translates to:
  /// **'Open **last.fm/api/account/create** and register an app — any name will do.'**
  String get lfmStep1;

  /// No description provided for @lfmStep2.
  ///
  /// In en, this message translates to:
  /// **'Copy **API Key** and **Shared Secret** from there and paste them into the fields below.'**
  String get lfmStep2;

  /// No description provided for @lfmStep3.
  ///
  /// In en, this message translates to:
  /// **'Tap **“Sign in with Last.fm”** — the browser opens, and the password is only entered there.'**
  String get lfmStep3;

  /// No description provided for @lfmStep4.
  ///
  /// In en, this message translates to:
  /// **'Allow access and come back to Bloom: the app checks the sign-in by itself.'**
  String get lfmStep4;

  /// No description provided for @lfmGuideNote.
  ///
  /// In en, this message translates to:
  /// **'The key has to be your own — Bloom has no shared Last.fm key. Your password is never entered into the app.'**
  String get lfmGuideNote;

  /// desktop: lastfm.oauth.gettingToken
  ///
  /// In en, this message translates to:
  /// **'Getting token…'**
  String get lfmGettingToken;

  /// desktop: lastfm.oauth.confirmAccess
  ///
  /// In en, this message translates to:
  /// **'Confirm access on Last.fm, then press “Done”'**
  String get lfmConfirmAccess;

  /// desktop: lastfm.oauth.checking
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get lfmChecking;

  /// desktop: lastfm.oauth.notConfirmed
  ///
  /// In en, this message translates to:
  /// **'Not confirmed — try again'**
  String get lfmNotConfirmed;

  /// desktop: lastfm.oauth.loginFirst
  ///
  /// In en, this message translates to:
  /// **'Press “Sign in with Last.fm” first'**
  String get lfmLoginFirst;

  /// desktop: lastfm.toast.saveApiKeyFirst + lastfm.toast.enterBothKeys, merged into one reason
  ///
  /// In en, this message translates to:
  /// **'Save the API Key and Secret first'**
  String get lfmNeedKeys;

  /// desktop: lastfm.oauth.networkError
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get lfmNetworkError;

  /// desktop: lastfm.oauth.error
  ///
  /// In en, this message translates to:
  /// **'Error: {msg}'**
  String lfmError(String msg);

  /// desktop: lastfm.toast.connectedAs
  ///
  /// In en, this message translates to:
  /// **'Last.fm: connected as {name}'**
  String lfmToastConnected(String name);

  /// desktop: lastfm.toast.disconnected
  ///
  /// In en, this message translates to:
  /// **'Last.fm: disconnected'**
  String get lfmToastDisconnected;

  /// desktop: lastfm.toast.keysSaved
  ///
  /// In en, this message translates to:
  /// **'Last.fm: keys saved'**
  String get lfmToastKeysSaved;

  /// desktop: notif.title — the notification centre sheet behind the bell
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifCenterTitle;

  /// desktop: notif.empty
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get notifCenterEmpty;

  /// desktop: notif.trackDl.title
  ///
  /// In en, this message translates to:
  /// **'Track downloaded'**
  String get notifTrackDownloaded;

  /// desktop: notif.dlError.title
  ///
  /// In en, this message translates to:
  /// **'Download error'**
  String get notifDownloadError;

  /// desktop: notif.offline.title
  ///
  /// In en, this message translates to:
  /// **'Track available offline'**
  String get notifOfflineReady;

  /// desktop: notif.offlineError.title
  ///
  /// In en, this message translates to:
  /// **'Offline download failed'**
  String get notifOfflineError;

  /// desktop: notif.trackUnavailable.title
  ///
  /// In en, this message translates to:
  /// **'Track unavailable'**
  String get notifTrackUnavailable;

  /// desktop: wrapped.title
  ///
  /// In en, this message translates to:
  /// **'Wrapped'**
  String get wrTitle;

  /// No description provided for @wrWeek.
  ///
  /// In en, this message translates to:
  /// **'Week in review'**
  String get wrWeek;

  /// No description provided for @wrMonth.
  ///
  /// In en, this message translates to:
  /// **'Month in review'**
  String get wrMonth;

  /// No description provided for @wrYear.
  ///
  /// In en, this message translates to:
  /// **'Year in review'**
  String get wrYear;

  /// No description provided for @wrPrev.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get wrPrev;

  /// No description provided for @wrNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get wrNext;

  /// No description provided for @wrIntroWeek.
  ///
  /// In en, this message translates to:
  /// **'Your week in Bloom'**
  String get wrIntroWeek;

  /// No description provided for @wrIntroMonth.
  ///
  /// In en, this message translates to:
  /// **'Your month in Bloom'**
  String get wrIntroMonth;

  /// No description provided for @wrIntroYear.
  ///
  /// In en, this message translates to:
  /// **'Your year in Bloom'**
  String get wrIntroYear;

  /// No description provided for @wrIntroSub.
  ///
  /// In en, this message translates to:
  /// **'LetвЂ™s see how it went'**
  String get wrIntroSub;

  /// No description provided for @wrTimeKicker.
  ///
  /// In en, this message translates to:
  /// **'You listened for'**
  String get wrTimeKicker;

  /// No description provided for @wrTimeSub.
  ///
  /// In en, this message translates to:
  /// **'Plays in this period: {count}'**
  String wrTimeSub(int count);

  /// No description provided for @wrTimeLessThanMin.
  ///
  /// In en, this message translates to:
  /// **'Less than a minute'**
  String get wrTimeLessThanMin;

  /// No description provided for @wrCountsKicker.
  ///
  /// In en, this message translates to:
  /// **'In numbers'**
  String get wrCountsKicker;

  /// No description provided for @wrCountsTitle.
  ///
  /// In en, this message translates to:
  /// **'HereвЂ™s the whole picture'**
  String get wrCountsTitle;

  /// No description provided for @wrCountsNewTracks.
  ///
  /// In en, this message translates to:
  /// **'Heard for the first time: {count}'**
  String wrCountsNewTracks(int count);

  /// No description provided for @wrTracksKicker.
  ///
  /// In en, this message translates to:
  /// **'On repeat'**
  String get wrTracksKicker;

  /// No description provided for @wrTracksTitle.
  ///
  /// In en, this message translates to:
  /// **'Your top tracks'**
  String get wrTracksTitle;

  /// No description provided for @wrTracksTitleOne.
  ///
  /// In en, this message translates to:
  /// **'Your track of the period'**
  String get wrTracksTitleOne;

  /// No description provided for @wrArtistsKicker.
  ///
  /// In en, this message translates to:
  /// **'Voices of the period'**
  String get wrArtistsKicker;

  /// No description provided for @wrArtistsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your top artists'**
  String get wrArtistsTitle;

  /// No description provided for @wrArtistsTitleOne.
  ///
  /// In en, this message translates to:
  /// **'Your artist of the period'**
  String get wrArtistsTitleOne;

  /// No description provided for @wrSourcesKicker.
  ///
  /// In en, this message translates to:
  /// **'Where it came from'**
  String get wrSourcesKicker;

  /// No description provided for @wrSourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Where you listened'**
  String get wrSourcesTitle;

  /// No description provided for @wrDiscoverKicker.
  ///
  /// In en, this message translates to:
  /// **'New names'**
  String get wrDiscoverKicker;

  /// No description provided for @wrDiscoverTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{You discovered {count} artist} other{You discovered {count} artists}}'**
  String wrDiscoverTitle(int count);

  /// No description provided for @wrHabitsKicker.
  ///
  /// In en, this message translates to:
  /// **'Your habits'**
  String get wrHabitsKicker;

  /// No description provided for @wrHabitsNight.
  ///
  /// In en, this message translates to:
  /// **'YouвЂ™re a night listener'**
  String get wrHabitsNight;

  /// No description provided for @wrHabitsDay.
  ///
  /// In en, this message translates to:
  /// **'YouвЂ™re a daytime listener'**
  String get wrHabitsDay;

  /// No description provided for @wrHabitsPeak.
  ///
  /// In en, this message translates to:
  /// **'Favorite hour'**
  String get wrHabitsPeak;

  /// No description provided for @wrHabitsRecord.
  ///
  /// In en, this message translates to:
  /// **'Day record'**
  String get wrHabitsRecord;

  /// No description provided for @wrHabitsStreak.
  ///
  /// In en, this message translates to:
  /// **'Days in a row'**
  String get wrHabitsStreak;

  /// No description provided for @wrHabitsActive.
  ///
  /// In en, this message translates to:
  /// **'Days with music'**
  String get wrHabitsActive;

  /// tracks is an already-formatted wrTracksN string
  ///
  /// In en, this message translates to:
  /// **'{tracks} В· {date}'**
  String wrHabitsRecordValue(Object tracks, Object date);

  /// No description provided for @wrShareKicker.
  ///
  /// In en, this message translates to:
  /// **'Keep it'**
  String get wrShareKicker;

  /// No description provided for @wrShareSave.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get wrShareSave;

  /// No description provided for @wrShareFail.
  ///
  /// In en, this message translates to:
  /// **'CouldnвЂ™t share the card'**
  String get wrShareFail;

  /// No description provided for @wrCardTime.
  ///
  /// In en, this message translates to:
  /// **'Time with music'**
  String get wrCardTime;

  /// No description provided for @wrCardTopTracks.
  ///
  /// In en, this message translates to:
  /// **'Top tracks'**
  String get wrCardTopTracks;

  /// No description provided for @wrCardTopArtists.
  ///
  /// In en, this message translates to:
  /// **'Top artists'**
  String get wrCardTopArtists;

  /// No description provided for @wrJokeTiny.
  ///
  /// In en, this message translates to:
  /// **'Kind of empty. Did you even press play?'**
  String get wrJokeTiny;

  /// No description provided for @wrJokeSmall.
  ///
  /// In en, this message translates to:
  /// **'Modest. But we counted every single track.'**
  String get wrJokeSmall;

  /// No description provided for @wrJokeOneTrack.
  ///
  /// In en, this message translates to:
  /// **'One track, one artist вЂ” respect the consistency.'**
  String get wrJokeOneTrack;

  /// No description provided for @wrPlaysN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} play} other{{count} plays}}'**
  String wrPlaysN(int count);

  /// the noun alone, for tiles where the number is rendered separately
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{play} other{plays}}'**
  String wrPlaysWord(int count);

  /// No description provided for @wrTracksN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} track} other{{count} tracks}}'**
  String wrTracksN(int count);

  /// No description provided for @wrTracksWord.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{track} other{tracks}}'**
  String wrTracksWord(int count);

  /// No description provided for @wrArtistsN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} artist} other{{count} artists}}'**
  String wrArtistsN(int count);

  /// No description provided for @wrArtistsWord.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{artist} other{artists}}'**
  String wrArtistsWord(int count);

  /// No description provided for @wrDaysN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} day} other{{count} days}}'**
  String wrDaysN(int count);

  /// No description provided for @wrHoursN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} hour} other{{count} hours}}'**
  String wrHoursN(int count);

  /// No description provided for @wrMinutesN.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} minute} other{{count} minutes}}'**
  String wrMinutesN(int count);

  /// favorite hour, both sides already formatted as HH:00
  ///
  /// In en, this message translates to:
  /// **'{from} вЂ” {to}'**
  String wrHourRange(Object from, Object to);

  /// No description provided for @wrSetCaption.
  ///
  /// In en, this message translates to:
  /// **'WRAPPED'**
  String get wrSetCaption;

  /// No description provided for @wrSetShow.
  ///
  /// In en, this message translates to:
  /// **'Show Wrapped'**
  String get wrSetShow;

  /// No description provided for @wrSetShowSub.
  ///
  /// In en, this message translates to:
  /// **'A story circle on the home screen when thereвЂ™s something to sum up'**
  String get wrSetShowSub;

  /// No description provided for @wrSetAlways.
  ///
  /// In en, this message translates to:
  /// **'Always show'**
  String get wrSetAlways;

  /// No description provided for @wrSetAlwaysSub.
  ///
  /// In en, this message translates to:
  /// **'Skip the schedule вЂ” open wrapped on any day'**
  String get wrSetAlwaysSub;

  /// desktop: settings.system.startup
  ///
  /// In en, this message translates to:
  /// **'Startup'**
  String get sysStartup;

  /// No description provided for @audRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore the queue'**
  String get audRestoreTitle;

  /// No description provided for @audRestoreSub.
  ///
  /// In en, this message translates to:
  /// **'Bring the track, queue and position back on launch — paused'**
  String get audRestoreSub;

  /// desktop: settings.system.autoplay.title
  ///
  /// In en, this message translates to:
  /// **'Autoplay'**
  String get audAutoplayTitle;

  /// desktop: settings.system.autoplay.sub
  ///
  /// In en, this message translates to:
  /// **'Restore the last session on launch and keep playing right away'**
  String get audAutoplaySub;

  /// desktop: settings.about.version
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersion;

  /// No description provided for @aboutCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get aboutCheck;

  /// desktop: settings.about.uptodate
  ///
  /// In en, this message translates to:
  /// **'You have the latest version'**
  String get aboutUptodate;

  /// desktop: settings.about.available
  ///
  /// In en, this message translates to:
  /// **'Version {v} is available'**
  String aboutAvailable(String v);

  /// desktop: settings.about.error
  ///
  /// In en, this message translates to:
  /// **'Couldn’t check for updates'**
  String get aboutError;

  /// No description provided for @aboutOpenRelease.
  ///
  /// In en, this message translates to:
  /// **'Open the release page'**
  String get aboutOpenRelease;

  /// No description provided for @updSection.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updSection;

  /// desktop: update.whatsNew
  ///
  /// In en, this message translates to:
  /// **'What’s new'**
  String get updWhatsNew;

  /// No description provided for @updWhatsNewSub.
  ///
  /// In en, this message translates to:
  /// **'Notes for the installed version'**
  String get updWhatsNewSub;

  /// desktop: update.history
  ///
  /// In en, this message translates to:
  /// **'Update history'**
  String get updHistory;

  /// No description provided for @updHistorySub.
  ///
  /// In en, this message translates to:
  /// **'Notes for previous versions'**
  String get updHistorySub;

  /// desktop: update.historyEmpty
  ///
  /// In en, this message translates to:
  /// **'There are no release notes yet'**
  String get updHistoryEmpty;

  /// desktop: update.notesEmpty
  ///
  /// In en, this message translates to:
  /// **'No notes for this version'**
  String get updNotesEmpty;

  /// No description provided for @updNotesError.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load the release notes'**
  String get updNotesError;

  /// desktop: settings.system.importExport
  ///
  /// In en, this message translates to:
  /// **'Import/Export'**
  String get sysImportExport;

  /// desktop: settings.system.exportAll.title
  ///
  /// In en, this message translates to:
  /// **'Export all'**
  String get sysExportTitle;

  /// No description provided for @sysExportSub.
  ///
  /// In en, this message translates to:
  /// **'Save every playlist to a .bloomplaylist file'**
  String get sysExportSub;

  /// desktop: settings.system.export.filename
  ///
  /// In en, this message translates to:
  /// **'bloom-playlists.bloomplaylist'**
  String get sysExportFilename;

  /// No description provided for @sysExported.
  ///
  /// In en, this message translates to:
  /// **'File saved'**
  String get sysExported;

  /// No description provided for @sysNoPlaylists.
  ///
  /// In en, this message translates to:
  /// **'There are no playlists yet'**
  String get sysNoPlaylists;

  /// desktop: settings.system.import.title
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get sysImportTitle;

  /// No description provided for @sysImportSub.
  ///
  /// In en, this message translates to:
  /// **'Load playlists from a .bloomplaylist file'**
  String get sysImportSub;

  /// desktop: settings.system.toast.importInvalid
  ///
  /// In en, this message translates to:
  /// **'Error: invalid file'**
  String get sysImportInvalid;

  /// No description provided for @sysImportNoPlaylists.
  ///
  /// In en, this message translates to:
  /// **'No playlists found'**
  String get sysImportNoPlaylists;

  /// desktop: settings.system.toast.importedFull
  ///
  /// In en, this message translates to:
  /// **'Imported: {pl} pl., {tr} tr.'**
  String sysImportedFull(int pl, int tr);

  /// desktop: settings.system.toast.importedPlaylists
  ///
  /// In en, this message translates to:
  /// **'Playlists imported: {pl}'**
  String sysImportedPlaylists(int pl);

  /// desktop: settings.system.logs
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get sysLogs;

  /// desktop: settings.system.log.title
  ///
  /// In en, this message translates to:
  /// **'Activity log'**
  String get sysLogTitle;

  /// No description provided for @sysLogEmptySub.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet'**
  String get sysLogEmptySub;

  /// No description provided for @sysLogEntries.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{{count} entry} other{{count} entries}}'**
  String sysLogEntries(int count);

  /// desktop: logs.copy
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get logsCopy;

  /// No description provided for @logsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get logsSave;

  /// desktop: settings.system.log.clear
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get logsClear;

  /// desktop: logs.copied
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get logsCopied;

  /// desktop: settings.system.toast.logsSaved
  ///
  /// In en, this message translates to:
  /// **'Logs saved'**
  String get logsSaved;

  /// desktop: settings.system.toast.logsCleared
  ///
  /// In en, this message translates to:
  /// **'Logs cleared'**
  String get logsCleared;

  /// desktop: logs.empty
  ///
  /// In en, this message translates to:
  /// **'The log is empty'**
  String get logsEmpty;

  /// desktop: settings.system.dangerZone
  ///
  /// In en, this message translates to:
  /// **'Danger zone'**
  String get sysDangerZone;

  /// desktop: settings.system.resetSettings.title
  ///
  /// In en, this message translates to:
  /// **'Reset settings'**
  String get sysResetTitle;

  /// desktop: settings.system.resetSettings.sub
  ///
  /// In en, this message translates to:
  /// **'Return the look and the options to their defaults'**
  String get sysResetSub;

  /// No description provided for @sysResetBody.
  ///
  /// In en, this message translates to:
  /// **'The look, the player, gestures, transparency and customization presets go back to their defaults. Your library, history, profile and platform logins stay.'**
  String get sysResetBody;

  /// desktop: settings.system.resetSettings.btn
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get sysResetBtn;

  /// No description provided for @sysResetDone.
  ///
  /// In en, this message translates to:
  /// **'Settings reset'**
  String get sysResetDone;

  /// desktop: settings.system.hardReset.title
  ///
  /// In en, this message translates to:
  /// **'Reset everything'**
  String get sysHardResetTitle;

  /// desktop: settings.system.hardReset.sub
  ///
  /// In en, this message translates to:
  /// **'Delete tracks, playlists, history and settings'**
  String get sysHardResetSub;

  /// No description provided for @sysHardResetBody.
  ///
  /// In en, this message translates to:
  /// **'The library, playlists, history, profile, downloads and every setting will be erased for good. There will be nothing to bring them back with.'**
  String get sysHardResetBody;

  /// desktop: settings.system.hardReset.btn
  ///
  /// In en, this message translates to:
  /// **'Reset everything'**
  String get sysHardResetBtn;

  /// No description provided for @sysHardResetDone.
  ///
  /// In en, this message translates to:
  /// **'Everything is erased'**
  String get sysHardResetDone;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
