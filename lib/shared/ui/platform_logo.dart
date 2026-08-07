/// Логотипы площадок и сервисов — те же SVG, что в десктопном Bloom
/// (`src/shared/assets/`).
///
/// Рисуются В СВОИХ ФИРМЕННЫХ ЦВЕТАХ: бренды не перекрашиваются под тему — то
/// же правило, по которому их названия не переводятся.
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/entities/entities.dart';

const Map<MusicSource, String> _assets = {
  MusicSource.soundcloud: 'assets/platform/soundcloud.svg',
  MusicSource.ytmusic: 'assets/platform/YouTube.svg',
  MusicSource.yandex: 'assets/platform/yandex_music.svg',
};

/// Фирменный цвет площадки — для акцентов там, где логотип не влезает.
const Map<MusicSource, Color> platformColor = {
  MusicSource.soundcloud: Color(0xFFFF5500),
  MusicSource.ytmusic: Color(0xFFFF0000),
  MusicSource.yandex: Color(0xFFFFCC00),
};

/// Логотип площадки. У локальных файлов логотипа нет — рисуем пустоту.
class PlatformLogo extends StatelessWidget {
  const PlatformLogo(this.source, {super.key, this.size = 16});

  final MusicSource source;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = _assets[source];
    if (asset == null) return SizedBox(width: size, height: size);
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

/// Сервис-интеграция (настройки: Last.fm, Genius, Discord).
enum Service { lastfm, genius, discord }

const Map<Service, String> _serviceAssets = {
  Service.lastfm: 'assets/platform/last-fm.svg',
  Service.genius: 'assets/platform/genius.svg',
  Service.discord: 'assets/platform/Discord.svg',
};

/// Эти три знака одноцветные, и в файлах залиты ЧЁРНЫМ — на тёмной теме их
/// просто не видно. Поэтому, в отличие от логотипов площадок, красим их сами:
/// в фирменный цвет сервиса, силуэт при этом не меняется.
const Map<Service, Color> serviceColor = {
  Service.lastfm: Color(0xFFD51007),
  Service.genius: Color(0xFFFFFF64),
  Service.discord: Color(0xFF5865F2),
};

class ServiceLogo extends StatelessWidget {
  const ServiceLogo(this.service, {super.key, this.size = 16, this.color});

  final Service service;
  final double size;

  /// Переопределить цвет (например приглушить у ещё не подключённого сервиса).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _serviceAssets[service]!,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(
        color ?? serviceColor[service]!,
        BlendMode.srcIn,
      ),
    );
  }
}
