/// «Моя волна» от Яндекса (rotor) — порт `src/wave/yandex.ts`.
///
/// Отдельный драйвер очереди: механика плеера та же, что у своего движка
/// (очередь + источник «волна»), но треки приходят готовой станцией, а не
/// собираются подбором. Отсюда и различия:
///   • ни фильтров, ни скоринга — станция уже всё решила;
///   • фидбек уходит обратно в аккаунт, и «Моя волна» учится там, а не у нас;
///   • сеанс не переживает перезапуск: rotor всё равно отдаёт свежую цепочку.
library;

import 'dart:async';

import '../../core/entities/entities.dart';
import '../../providers/yandex/ym_provider.dart' show trackFromYm, ymNumericId;
import '../../providers/yandex/yandex.dart' as ym;

/// Догружаем, когда впереди осталось столько треков.
const int kRotorRefillThreshold = 4;

/// Ниже этой доли трека уход считается скипом.
const double _kSkipRatio = 0.3;

class _RotorState {
  _RotorState(this.station);

  /// Сид станции: `user:onyourwave`, `track:<id>`, `artist:<id>`.
  final String station;
  String batchId = '';

  /// id последнего трека из выдачи — курсор следующей пачки.
  String lastId = '';

  /// Поколение сеанса: ответ на догрузку, начатую до перезапуска станции, не
  /// должен дописаться в чужую очередь.
  int generation = 0;
}

class YandexRotor {
  _RotorState? _state;
  bool _refilling = false;

  /// Идёт ли сеанс станции.
  bool get isRunning => _state != null;

  String get station => _state?.station ?? '';

  /// Станция «Моей волны».
  static String get personalStation => ym.kWaveStation;
  static String trackStation(String ymTrackId) => 'track:$ymTrackId';
  static String artistStation(String ymArtistId) => 'artist:$ymArtistId';

  /// Начать станцию. Пустой список — станция ничего не отдала; вызывающий
  /// решает, что сказать человеку. Бросает [ym.YmException] сетевых ошибок.
  Future<List<Track>> start(String station) async {
    final batch = await ym.waveTracks(station);
    if (batch.tracks.isEmpty) {
      _state = null;
      return const [];
    }
    final prev = _state?.generation ?? 0;
    _state = _RotorState(station)
      ..batchId = batch.batchId
      ..lastId = batch.tracks.last.id
      ..generation = prev + 1;

    unawaited(_feedback('radioStarted'));
    return [for (final raw in batch.tracks) trackFromYm(raw)];
  }

  /// Фидбек «трек пошёл»: по нему станция и понимает, что предложенное
  /// действительно слушают.
  void trackStarted(Track track) {
    final id = _ymIdOf(track);
    if (id != null) unawaited(_feedback('trackStarted', trackId: id));
  }

  /// Фидбек об уходе с трека — главный сигнал обучения станции.
  void trackEnded(Track track, Duration played, Duration total) {
    final id = _ymIdOf(track);
    if (id == null) return;
    final ratio = total > Duration.zero
        ? played.inMilliseconds / total.inMilliseconds
        : 0.0;
    unawaited(
      _feedback(
        ratio < _kSkipRatio ? 'skip' : 'trackFinished',
        trackId: id,
        played: played.inMilliseconds / 1000,
      ),
    );
  }

  /// Догрузить следующую пачку. Пустой список — догружать нечего (или сеанс
  /// уже сменился, пока мы ждали сеть).
  Future<List<Track>> refill() async {
    final state = _state;
    if (state == null || _refilling) return const [];
    _refilling = true;
    final generation = state.generation;
    try {
      final batch = await ym.waveTracks(state.station, lastId: state.lastId);
      // Сеанс могли остановить или начать заново — не пишем в чужую очередь.
      final now = _state;
      if (now == null || now.generation != generation) return const [];
      if (batch.tracks.isEmpty) return const [];
      if (batch.batchId.isNotEmpty) now.batchId = batch.batchId;
      now.lastId = batch.tracks.last.id;
      return [for (final raw in batch.tracks) trackFromYm(raw)];
    } catch (_) {
      // Сеть моргнула — следующая смена трека попробует снова.
      return const [];
    } finally {
      _refilling = false;
    }
  }

  void end() {
    _state = null;
  }

  Future<void> _feedback(
    String event, {
    String trackId = '',
    double played = 0,
  }) {
    final state = _state;
    if (state == null) return Future.value();
    return ym.waveFeedback(
      station: state.station,
      event: event,
      trackId: trackId,
      batchId: state.batchId,
      played: played,
    );
  }

  /// Числовой id Яндекса из сквозного. `null` — трек не с этой площадки, и
  /// станции о нём сказать нечего.
  static String? _ymIdOf(Track track) {
    if (track.source != MusicSource.yandex) return null;
    final id = ymNumericId(track.id);
    return id.isEmpty ? null : id;
  }
}
