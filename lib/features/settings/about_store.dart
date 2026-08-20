/// «О приложении»: версия сборки и проверка обновлений — порт десктопных
/// `AboutBlock.tsx` + `updateStore.ts`, урезанный до того, что мобилка умеет.
///
/// На ПК обновление скачивается и ставится самим приложением (плагин
/// `tauri-updater`). На телефоне так нельзя: APK ставит система, из App Store
/// приложение обновляется само, и никакой установщик мы не пишем. Поэтому здесь
/// осталась ровно проверка: сходить в GitHub Releases, сравнить версии и, если
/// вышла новее, дать кнопку «Открыть страницу релиза» — дальше человек качает
/// APK сам.
///
/// Заметки к версиям (`update-notes` с ПК) не переносились: их манифест лежит в
/// десктопном репозитории и описывает десктопные релизы.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/log/bloom_log.dart';
import '../../core/store/text_files.dart';

/// Репозиторий мобильного Bloom — тот же, куда `.github/workflows/release.yml`
/// кладёт APK. Теги там вида `v1.2.3`.
const String kUpdateRepo = 'bxzlik/Bloom-Mobile';

Uri get _latestReleaseUrl =>
    Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest');

/// Что показывает блок «О приложении».
enum UpdatePhase { idle, checking, uptodate, available, error }

class AboutState {
  const AboutState({
    this.version = '',
    this.phase = UpdatePhase.idle,
    this.latest = '',
    this.releaseUrl = '',
  });

  /// Версия установленной сборки (`1.0.0`); пусто — платформа не ответила.
  ///
  /// Номер сборки (`versionCode`) рядом не показываем: он растёт от каждой
  /// сборки CI и человеку ничего не говорит, а сравнивать с релизом мы всё
  /// равно будем по версии.
  final String version;

  final UpdatePhase phase;

  /// Версия последнего релиза без `v` — есть только после успешной проверки.
  final String latest;
  final String releaseUrl;

  AboutState copyWith({
    String? version,
    UpdatePhase? phase,
    String? latest,
    String? releaseUrl,
  }) => AboutState(
    version: version ?? this.version,
    phase: phase ?? this.phase,
    latest: latest ?? this.latest,
    releaseUrl: releaseUrl ?? this.releaseUrl,
  );
}

/// Как ходим за релизом. Отдельным провайдером ради тестов: сеть в них
/// подменяется, как `lastfmTransport` у Last.fm.
typedef ReleaseFetch = Future<String> Function(Uri url);

final releaseFetchProvider = Provider<ReleaseFetch>((ref) => _get);

Future<String> _get(Uri url) async {
  final res = await http.get(
    url,
    headers: {'Accept': 'application/vnd.github+json'},
  );
  if (res.statusCode != 200) {
    throw http.ClientException('HTTP ${res.statusCode}', url);
  }
  return res.body;
}

final aboutProvider = NotifierProvider<AboutController, AboutState>(
  AboutController.new,
);

class AboutController extends Notifier<AboutState> {
  @override
  AboutState build() => const AboutState();

  /// Прочитать версию у платформы. Идемпотентно — экран зовёт её при каждом
  /// открытии, а ответ не меняется до переустановки.
  Future<void> loadVersion() async {
    if (state.version.isNotEmpty) return;
    final info = await appVersion();
    if (info == null) return;
    state = state.copyWith(version: info.version);
  }

  /// Сходить за последним релизом. Второй вызов, пока идёт первый, игнорируем.
  Future<void> check() async {
    if (state.phase == UpdatePhase.checking) return;
    state = state.copyWith(phase: UpdatePhase.checking);
    try {
      final body = await ref.read(releaseFetchProvider)(_latestReleaseUrl);
      final json = jsonDecode(body);
      if (json is! Map) throw const FormatException('не JSON-объект');
      final tag = json['tag_name'];
      if (tag is! String || tag.isEmpty) {
        throw const FormatException('в ответе нет tag_name');
      }
      final latest = normalizeVersion(tag);
      final url =
          json['html_url'] as String? ??
          'https://github.com/$kUpdateRepo/releases';
      // Версия неизвестна (платформа не ответила) — сравнивать не с чем, и
      // честнее показать «есть релиз N», чем соврать «установлена последняя».
      final newer =
          state.version.isEmpty || compareVersions(latest, state.version) > 0;
      state = state.copyWith(
        phase: newer ? UpdatePhase.available : UpdatePhase.uptodate,
        latest: latest,
        releaseUrl: url,
      );
    } catch (e) {
      logWarn('update', 'проверка обновлений не удалась: $e');
      state = state.copyWith(phase: UpdatePhase.error);
    }
  }
}

/// `v1.2.3` → `1.2.3`. Тег релиза, имя сборки и версия из манифеста должны
/// сравниваться в одном виде.
String normalizeVersion(String raw) {
  final v = raw.trim();
  return v.startsWith('v') || v.startsWith('V') ? v.substring(1) : v;
}

/// Сравнение версий по числовым частям — порт `cmpVer` с десктопа.
///
/// Разной длины сравниваются как дополненные нулями (`1.2` = `1.2.0`), нечисловой
/// хвост (`1.2.3-beta`) отбрасывается: у нас релизы нумеруются просто, а падать
/// из-за чужого тега проверка обновлений не должна.
int compareVersions(String a, String b) {
  final pa = _parts(a);
  final pb = _parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x > y ? 1 : -1;
  }
  return 0;
}

List<int> _parts(String v) => [
  for (final chunk in normalizeVersion(v).split('.'))
    int.tryParse(RegExp(r'^\d+').firstMatch(chunk)?.group(0) ?? '') ?? 0,
];
