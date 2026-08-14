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

  /// No description provided for @commonRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// desktop: common.undo — default toast action label
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get commonDiscard;

  /// No description provided for @commonUpload.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get commonUpload;

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

  /// No description provided for @playerPlayingFrom.
  ///
  /// In en, this message translates to:
  /// **'Playing from'**
  String get playerPlayingFrom;

  /// desktop: settings.view.mpEl.queue
  ///
  /// In en, this message translates to:
  /// **'Queue'**
  String get playerQueue;

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

  /// No description provided for @libDragHint.
  ///
  /// In en, this message translates to:
  /// **'In “Default” order a tile can be held and dragged'**
  String get libDragHint;

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

  /// No description provided for @tlSetCover.
  ///
  /// In en, this message translates to:
  /// **'Set a cover'**
  String get tlSetCover;

  /// No description provided for @tlChangeCover.
  ///
  /// In en, this message translates to:
  /// **'Change cover'**
  String get tlChangeCover;

  /// No description provided for @tlRemoveCover.
  ///
  /// In en, this message translates to:
  /// **'Remove cover'**
  String get tlRemoveCover;

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

  /// No description provided for @leDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {tracks}?'**
  String leDeleteTitle(String tracks);

  /// No description provided for @leDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'They will disappear from your library, likes, playlists and history.'**
  String get leDeleteBody;

  /// No description provided for @leDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get leDiscardTitle;

  /// No description provided for @leDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'Everything you changed in this list will be lost.'**
  String get leDiscardBody;

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
  /// **'Nothing to refresh: no playlist was imported from a link. Paste a link into the search field — an imported playlist remembers its source.'**
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

  /// desktop: settings.storage.offline
  ///
  /// In en, this message translates to:
  /// **'Offline track cache'**
  String get stOfflineCache;

  /// No description provided for @stCounting.
  ///
  /// In en, this message translates to:
  /// **'Counting…'**
  String get stCounting;

  /// No description provided for @stCacheStats.
  ///
  /// In en, this message translates to:
  /// **'{count} tracks · {size}'**
  String stCacheStats(int count, String size);

  /// No description provided for @stHelp.
  ///
  /// In en, this message translates to:
  /// **'Downloaded tracks play without a network and use no data. They live inside the app — other players can’t see them, and they are removed together with Bloom.'**
  String get stHelp;

  /// No description provided for @stClear.
  ///
  /// In en, this message translates to:
  /// **'Clear offline cache'**
  String get stClear;

  /// No description provided for @stClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear the offline cache?'**
  String get stClearTitle;

  /// No description provided for @stClearBody.
  ///
  /// In en, this message translates to:
  /// **'The downloaded copies will be deleted and those tracks will stop playing without a network. They stay in your library and playlists.'**
  String get stClearBody;

  /// No description provided for @stCleared.
  ///
  /// In en, this message translates to:
  /// **'Offline cache cleared, files deleted: {count}'**
  String stCleared(int count);

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
