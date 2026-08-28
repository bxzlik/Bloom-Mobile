/// Название площадки на языке интерфейса.
///
/// Отдельным файлом, а не полем enum: `MusicSource` живёт в слое сущностей и
/// про Flutter ничего не знает, а переводится там всего два значения —
/// остальные площадки называются брендом одинаково на всех языках.
library;

import '../entities/entities.dart';
import 'l10n.dart';

extension MusicSourceLabel on MusicSource {
  String label10n(AppLocalizations l) => switch (this) {
    MusicSource.local => l.sourceLocal,
    MusicSource.yandex => l.sourceYandex,
    MusicSource.soundcloud || MusicSource.ytmusic => label,
  };
}
