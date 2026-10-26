/// Профиль пользователя приложения — порт `Profile` ПК.
///
/// Хранит ТОЛЬКО данные карточки: ник, био, статус, картинки и их цвета.
/// Счётчиков прослушиваний тут нет и на ПК тоже нет — статистика считается из
/// журнала.
///
/// Лежит в kv базы под ключом `profile` (вид ПК: цвета "#rrggbb", режим
/// обложки строкой), время первого запуска — `profile.since`. Сброс настроек
/// его не трогает, «Сбросить всё» уносит вместе с базой. Аватар и баннер лежат
/// файлами в каталоге приложения, в профиле от них только `local:<имя>` (см.
/// `cover_store`): контейнер iOS переезжает между запусками, и абсолютный путь
/// завтра указывал бы в пустоту.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/db.dart';
import '../../core/l10n/l10n.dart';

/// Обложка профиля без своей картинки: тон обложки самого слушаемого трека
/// (по умолчанию, как на ПК), сплошной цвет или градиент между двумя.
enum BannerColorMode { auto, solid, gradient }

/// Углы градиента обложки — те же восемь, что в редакторе ПК.
const List<int> kBannerAngles = [0, 45, 90, 135, 180, 225, 270, 315];

/// Длины полей — те же, что на ПК: ник, о себе, статус.
const int kNickMax = 32;
const int kBioMax = 300;
const int kStatusMax = 80;

const Color _kBannerColor = Color(0xFF1A1A1A);
const Color _kBannerColor2 = Color(0xFF0D0D0D);

const String _kCard = 'profile';
const String _kSince = 'profile.since';

@immutable
class UserProfile {
  /// Имя для показа. Пустое поле — имени никто не задавал: подставляется
  /// локализованное «Пользователь». Именно при отрисовке, а не при сохранении:
  /// иначе дефолт застыл бы на языке, который стоял в момент первого запуска.
  String displayName(AppLocalizations l) =>
      name.trim().isEmpty ? l.profileDefaultName : name;

  const UserProfile({
    this.name = '',
    this.bio = '',
    this.status = '',
    this.bannerColor = _kBannerColor,
    this.bannerColor2 = _kBannerColor2,
    this.bannerMode = BannerColorMode.auto,
    this.bannerAngle = 135,
    this.avatar,
    this.banner,
  });

  final String name;
  final String bio;
  final String status;

  final Color bannerColor;
  final Color bannerColor2;
  final BannerColorMode bannerMode;
  final int bannerAngle;

  /// `local:<имя файла>` своей картинки; `null` — заглушка с человечком.
  final String? avatar;

  /// `local:<имя файла>` своей обложки; `null` — цвет/градиент/тон.
  final String? banner;

  /// Есть ли что показывать в боксе под ником.
  bool get hasAbout => bio.trim().isNotEmpty || status.trim().isNotEmpty;

  UserProfile copyWith({
    String? name,
    String? bio,
    String? status,
    Color? bannerColor,
    Color? bannerColor2,
    BannerColorMode? bannerMode,
    int? bannerAngle,
    String? avatar,
    bool clearAvatar = false,
    String? banner,
    bool clearBanner = false,
  }) => UserProfile(
    name: name ?? this.name,
    bio: bio ?? this.bio,
    status: status ?? this.status,
    bannerColor: bannerColor ?? this.bannerColor,
    bannerColor2: bannerColor2 ?? this.bannerColor2,
    bannerMode: bannerMode ?? this.bannerMode,
    bannerAngle: bannerAngle ?? this.bannerAngle,
    avatar: clearAvatar ? null : (avatar ?? this.avatar),
    banner: clearBanner ? null : (banner ?? this.banner),
  );

  /// Вид ПК: пустые картинки — пустой строкой, а не пропущенным полем.
  Map<String, dynamic> toJson() => {
    'name': name,
    'bio': bio,
    'status': status,
    'avatar': avatar ?? '',
    'banner': banner ?? '',
    'bannerMode': bannerMode.name,
    'bannerColor': hexOf(bannerColor),
    'bannerColor2': hexOf(bannerColor2),
    'bannerAngle': bannerAngle,
  };

  /// Из kv (или, потом, с другого устройства), целым: чего нет или что
  /// кривое — по умолчанию, текст обрезан до длин ПК (`normalized` ПК).
  static UserProfile fromJson(Map<String, dynamic> json) {
    String text(String key, int max) {
      final s = (json[key] as String? ?? '').trim();
      return s.characters.take(max).toString();
    }

    String? file(String key) {
      final raw = json[key];
      return raw is String && raw.isNotEmpty ? raw : null;
    }

    final angle = (json['bannerAngle'] as num?)?.toInt() ?? 135;
    return UserProfile(
      name: text('name', kNickMax),
      bio: text('bio', kBioMax),
      status: text('status', kStatusMax),
      bannerColor: colorOf(json['bannerColor']) ?? _kBannerColor,
      bannerColor2: colorOf(json['bannerColor2']) ?? _kBannerColor2,
      bannerMode: BannerColorMode.values.asNameMap()[json['bannerMode']] ??
          BannerColorMode.auto,
      bannerAngle: (angle % 360 + 360) % 360,
      avatar: file('avatar'),
      banner: file('banner'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.name == name &&
      other.bio == bio &&
      other.status == status &&
      other.bannerColor == bannerColor &&
      other.bannerColor2 == bannerColor2 &&
      other.bannerMode == bannerMode &&
      other.bannerAngle == bannerAngle &&
      other.avatar == avatar &&
      other.banner == banner;

  @override
  int get hashCode => Object.hash(
    name,
    bio,
    status,
    bannerColor,
    bannerColor2,
    bannerMode,
    bannerAngle,
    avatar,
    banner,
  );
}

/// "#rrggbb", как `QColor::name()` ПК.
String hexOf(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// "#rgb" / "#rrggbb" → цвет; всё остальное — `null`.
Color? colorOf(Object? raw) {
  if (raw is! String || !raw.startsWith('#')) return null;
  var hex = raw.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length != 6) return null;
  final v = int.tryParse(hex, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

final profileProvider = NotifierProvider<ProfileController, UserProfile>(
  ProfileController.new,
);

class ProfileController extends Notifier<UserProfile> {
  BloomDb get _db => ref.read(dbProvider);

  @override
  UserProfile build() {
    // Профиль читает шапка главной при запуске — тогда и ставится «С нами с»,
    // а не при первом заходе на страницу профиля.
    ref.read(profileSinceProvider);
    return UserProfile.fromJson(_db.getMap(_kCard));
  }

  /// Перечитать из kv — пришёл профиль с ПК.
  void reload() => state = UserProfile.fromJson(_db.getMap(_kCard));

  /// Записать профиль целиком: правка идёт черновиком в редакторе и приходит
  /// сюда одним куском по «Сохранить». Пишется уже приведённым — тем, что
  /// прочитается в следующий раз.
  void save(UserProfile profile) {
    final card = UserProfile.fromJson(profile.toJson());
    if (card == state) return;
    _db.set(_kCard, card.toJson());
    state = card;
  }
}

/// Когда Bloom впервые запустили на этом устройстве — «С нами с». Ставится
/// при первом чтении, как на ПК; «Сбросить всё» стирает и его.
final profileSinceProvider = Provider<DateTime>((ref) {
  final db = ref.read(dbProvider);
  var ms = (db.get(_kSince, 0) as num?)?.toInt() ?? 0;
  if (ms <= 0) {
    ms = BloomDb.now();
    db.set(_kSince, ms);
  }
  return DateTime.fromMillisecondsSinceEpoch(ms);
});
