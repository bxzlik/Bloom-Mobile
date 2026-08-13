/// Аватары исполнителей для топа статистики — порт десктопного
/// `useArtistAvatars`.
///
/// В истории от артиста остаётся одно имя, поэтому настоящий аватар приходится
/// искать у площадки по имени. Ответ (в том числе пустой — «не нашли»)
/// кешируется на 30 дней: без этого каждое открытие профиля дёргало бы сеть на
/// десять запросов, а промахи — снова и снова.
///
/// Загрузка фоновая и необязательная: сети нет или площадка не настроена —
/// в топе просто остаётся обложка самого слушаемого трека артиста.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/providers/artist_lookup.dart';
import '../../core/store/library_store.dart' show jsonStoreProvider;

/// Столько живёт запись кеша — как `TTL` на десктопе.
const Duration _ttl = Duration(days: 30);

/// Где спрашиваем аватары. Десктоп ходит прямо в SoundCloud; здесь то же самое,
/// но через реестр — появится вторая площадка, будет что подставить.
const String _sourceId = 'soundcloud';

class _Cached {
  const _Cached(this.url, this.at);

  /// Пустая строка — искали и не нашли. Тоже кешируется.
  final String url;
  final int at;
}

final artistAvatarsProvider =
    NotifierProvider<ArtistAvatarsController, Map<String, String>>(
      ArtistAvatarsController.new,
    );

class ArtistAvatarsController extends Notifier<Map<String, String>> {
  final Map<String, _Cached> _cache = {};

  /// Кого уже спросили в этом запуске — чтобы параллельные перестройки списка
  /// не отправили десять одинаковых запросов.
  final Set<String> _inFlight = {};

  /// Загрузка асинхронная, а стор могут выбросить раньше её конца.
  bool _disposed = false;

  @override
  Map<String, String> build() {
    ref.onDispose(() => _disposed = true);
    final raw = ref.read(jsonStoreProvider).readMap('artistAvatars');
    for (final e in raw.entries) {
      final v = e.value;
      if (v is! Map) continue;
      _cache[e.key] = _Cached(
        v['url'] as String? ?? '',
        (v['t'] as num?)?.toInt() ?? 0,
      );
    }
    return _visible();
  }

  Map<String, String> _visible() => {
    for (final e in _cache.entries)
      if (e.value.url.isNotEmpty) e.key: e.value.url,
  };

  void _save() {
    ref.read(jsonStoreProvider).write('artistAvatars', {
      for (final e in _cache.entries)
        e.key: {'url': e.value.url, 't': e.value.at},
    });
  }

  /// Догрузить недостающие аватары. Зовётся из UI при показе топа; лишние
  /// вызовы безвредны — свежий кеш ничего не запрашивает.
  Future<void> ensure(List<String> names) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final todo = <String>[];
    for (final name in names) {
      final key = name.toLowerCase();
      if (key.isEmpty || _inFlight.contains(key)) continue;
      final cached = _cache[key];
      if (cached != null && now - cached.at < _ttl.inMilliseconds) continue;
      todo.add(name);
      _inFlight.add(key);
    }
    if (todo.isEmpty) return;

    final provider = ref.read(registryProvider).byId(_sourceId);
    if (provider == null) {
      _inFlight.clear();
      return;
    }

    var changed = false;
    for (final name in todo) {
      final key = name.toLowerCase();
      String url = '';
      try {
        url = (await findArtistByName(provider, name))?.avatar ?? '';
      } catch (_) {
        // Сети нет или площадка отказала — запомним промах, чтобы не биться
        // об неё каждым открытием профиля.
      }
      _cache[key] = _Cached(url, DateTime.now().millisecondsSinceEpoch);
      _inFlight.remove(key);
      changed = true;
    }

    if (!changed || _disposed) return;
    _save();
    state = _visible();
  }
}
