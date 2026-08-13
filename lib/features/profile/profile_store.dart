/// Профиль пользователя приложения — порт десктопного `profileStore.ts`.
///
/// Хранит ТОЛЬКО данные карточки: ник, био, статус, картинки и их цвета.
/// Счётчиков прослушиваний тут нет и на десктопе тоже нет — статистика
/// считается из истории (её вкладка будет отдельным заходом).
///
/// Пишется в общий `bloom.json` (ключ `profile`) — то, чем на десктопе служит
/// `localStorage['bloom_profile']`. Аватар и баннер лежат файлами в каталоге
/// приложения, в профиле от них только `local:<имя>` (см. `cover_store`):
/// контейнер iOS переезжает между запусками, и абсолютный путь завтра указывал
/// бы в пустоту.
library;

import 'dart:math' show cos, sin, pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/store/library_store.dart' show jsonStoreProvider;

/// `common.defaultUser` из десктопного словаря.
const String kDefaultUserName = 'Пользователь';

/// Обложка профиля: сплошной цвет или градиент между двумя.
enum BannerColorMode { solid, gradient }

/// Углы градиента обложки — те же восемь, что в десктопной модалке.
const List<int> kBannerAngles = [0, 45, 90, 135, 180, 225, 270, 315];

@immutable
class UserProfile {
  const UserProfile({
    this.name = kDefaultUserName,
    this.bio = '',
    this.status = '',
    this.discIdx = 0,
    this.discColor,
    this.bannerColor = const Color(0xFF1A1A1A),
    this.bannerColor2 = const Color(0xFF0D0D0D),
    this.bannerMode = BannerColorMode.solid,
    this.bannerAngle = 135,
    this.avatar,
    this.banner,
  });

  final String name;
  final String bio;
  final String status;

  /// Индекс пресета винил-диска (дефолтный аватар), 0..5.
  final int discIdx;

  /// Свой цвет диска (перебивает пресет); `null` — пресет.
  final Color? discColor;

  final Color bannerColor;
  final Color bannerColor2;
  final BannerColorMode bannerMode;
  final int bannerAngle;

  /// `local:<имя файла>` своей картинки; `null` — винил-диск.
  final String? avatar;

  /// `local:<имя файла>` своей обложки; `null` — цвет/градиент.
  final String? banner;

  /// Есть ли что показывать в боксе под ником.
  bool get hasAbout => bio.trim().isNotEmpty || status.trim().isNotEmpty;

  /// Заливка обложки, когда своей картинки нет.
  ///
  /// CSS-угол считается от «вверх» по часовой стрелке, у [Alignment] ось Y
  /// смотрит вниз — отсюда разворот знаков.
  Decoration bannerDecoration() {
    if (bannerMode == BannerColorMode.solid) {
      return BoxDecoration(color: bannerColor);
    }
    final a = bannerAngle * pi / 180;
    final dx = sin(a);
    final dy = -cos(a);
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment(-dx, -dy),
        end: Alignment(dx, dy),
        colors: [bannerColor, bannerColor2],
      ),
    );
  }

  UserProfile copyWith({
    String? name,
    String? bio,
    String? status,
    int? discIdx,
    Color? discColor,
    bool clearDiscColor = false,
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
    discIdx: discIdx ?? this.discIdx,
    discColor: clearDiscColor ? null : (discColor ?? this.discColor),
    bannerColor: bannerColor ?? this.bannerColor,
    bannerColor2: bannerColor2 ?? this.bannerColor2,
    bannerMode: bannerMode ?? this.bannerMode,
    bannerAngle: bannerAngle ?? this.bannerAngle,
    avatar: clearAvatar ? null : (avatar ?? this.avatar),
    banner: clearBanner ? null : (banner ?? this.banner),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'bio': bio,
    'status': status,
    'discIdx': discIdx,
    if (discColor != null) 'discColor': discColor!.toARGB32(),
    'bannerColor': bannerColor.toARGB32(),
    'bannerColor2': bannerColor2.toARGB32(),
    'bannerMode': bannerMode.name,
    'bannerAngle': bannerAngle,
    if (avatar != null) 'avatar': avatar,
    if (banner != null) 'banner': banner,
  };

  static UserProfile fromJson(Map<String, dynamic> json) {
    Color? color(Object? raw) => raw is num ? Color(raw.toInt()) : null;
    String? text(Object? raw) =>
        raw is String && raw.isNotEmpty ? raw : null;

    final name = json['name'];
    return UserProfile(
      name: name is String && name.trim().isNotEmpty ? name : kDefaultUserName,
      bio: json['bio'] as String? ?? '',
      status: json['status'] as String? ?? '',
      discIdx: (json['discIdx'] as num?)?.toInt() ?? 0,
      discColor: color(json['discColor']),
      bannerColor: color(json['bannerColor']) ?? const Color(0xFF1A1A1A),
      bannerColor2: color(json['bannerColor2']) ?? const Color(0xFF0D0D0D),
      bannerMode: json['bannerMode'] == 'gradient'
          ? BannerColorMode.gradient
          : BannerColorMode.solid,
      bannerAngle: (json['bannerAngle'] as num?)?.toInt() ?? 135,
      avatar: text(json['avatar']),
      banner: text(json['banner']),
    );
  }
}

final profileProvider = NotifierProvider<ProfileController, UserProfile>(
  ProfileController.new,
);

class ProfileController extends Notifier<UserProfile> {
  @override
  UserProfile build() =>
      UserProfile.fromJson(ref.read(jsonStoreProvider).readMap('profile'));

  /// Записать профиль целиком: правка идёт черновиком в редакторе и приходит
  /// сюда одним куском по «Сохранить».
  void save(UserProfile profile) {
    state = profile;
    ref.read(jsonStoreProvider).write('profile', profile.toJson());
  }
}
