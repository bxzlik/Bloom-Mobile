/// Где приложение держит свои файлы — одна точка правды для всех хранилищ.
///
/// Каталогов два, и путать их нельзя:
///
/// - [appPrivateDir] — служебное: `bloom.json`, свои обложки плейлистов,
///   офлайн-копии треков. Пользователю там делать нечего.
/// - [appVisibleDir] — то, что человек скачал себе сам и должен найти. На iOS
///   это папка приложения в «Файлах»; на Android скачанные файлы уезжают в
///   общую «Музыку» мимо этого каталога (см. `MediaStoreSaver`), поэтому там
///   он не используется.
///
/// Зачем разделение: на iOS «Файлы» показывают ВЕСЬ `Documents`, стоит включить
/// `UIFileSharingEnabled`. Держи мы там же служебное — пользователь увидел бы
/// `bloom.json` и каталог офлайн-копий и мог бы их снести. Поэтому на iOS
/// служебное живёт в `Application Support`, который «Файлам» не виден.
///
/// На Android каталог остаётся прежним (`Documents` = приватный каталог
/// приложения, из файлового менеджера не виден вообще): менять его нельзя —
/// у тех, кто уже поставил Bloom, там лежит библиотека.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Служебный каталог: библиотека, обложки, офлайн-копии.
///
/// Создаём, если его нет: `Application Support` на свежей установке iOS может
/// отсутствовать, и первая же запись `bloom.json` ушла бы в никуда — библиотека
/// молча не сохранялась бы.
Future<Directory> appPrivateDir() async {
  final dir = Platform.isIOS
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

/// Каталог, который пользователь видит в системных «Файлах» (iOS).
Future<Directory> appVisibleDir() => getApplicationDocumentsDirectory();
