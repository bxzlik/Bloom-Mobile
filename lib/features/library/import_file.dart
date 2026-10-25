/// Импорт плейлистов файлом `.bloomplaylist` — общий поток для двух точек
/// входа: «+» библиотеки (десктопное «Из файла» в меню импорта) и «Настройки →
/// Система → Импорт».
///
/// Сам разбор файла живёт в `settings/data_transfer.dart`; здесь — системный
/// диалог, обращение к библиотеке и тост. Тост показывается прямо тут, а не в
/// вызывающем: исходов четыре, и раскладывать их по видам тоста в каждой точке
/// входа заново значило бы разойтись в формулировках.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/log/bloom_log.dart';
import '../../core/store/library_store.dart';
import '../../core/store/text_files.dart';
import '../../shared/ui/bloom_toast.dart';
import '../settings/data_transfer.dart';

/// Выбрать файл и завести из него плейлисты. Возвращает счётчики или `null`,
/// если импорта не случилось (диалог закрыли, файл не наш, плейлистов внутри
/// нет) — обо всём, кроме отмены, вызывающему уже сказал тост.
Future<ImportResult?> importPlaylistFile(
  WidgetRef ref,
  ScaffoldMessengerState messenger,
  AppLocalizations l,
) async {
  final content = await openTextFile();
  if (content == null) return null; // диалог закрыли — молча, как на ПК
  final result = await importPlaylistBundle(
    content,
    ref.read(libraryProvider),
    ref.read(libraryProvider.notifier),
  );
  if (result.failure case final failure?) {
    messenger.toast(switch (failure) {
      ImportFailure.bad => l.sysImportInvalid,
      ImportFailure.oldFormat => l.sysImportOld,
      ImportFailure.newer => l.sysImportNewer,
    }, kind: ToastKind.error);
    return null;
  }
  if (result.playlists == 0) {
    messenger.toast(l.sysImportNoPlaylists, kind: ToastKind.warn);
    return null;
  }
  logInfo('transfer', 'импорт: ${result.playlists} пл., ${result.tracks} тр.');
  messenger.toast(
    result.tracks > 0
        ? l.sysImportedFull(result.playlists, result.tracks)
        : l.sysImportedPlaylists(result.playlists),
    kind: ToastKind.success,
  );
  return result;
}
