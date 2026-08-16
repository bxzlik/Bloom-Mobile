/// Кастомизация: библиотека картинок, контексты, пресеты и их файл.
///
/// Проверяем то, что ломается тихо: удалённая картинка обязана пропасть и из
/// контекстов, и из пресетов (иначе фон остаётся ссылкой в никуда), своя
/// картинка фона обязана быть важнее «обложки трека как фон», а файл пресетов
/// — переживать круг «выгрузили → загрузили» с теми же картинками и без
/// дублей в библиотеке.
library;

import 'package:bloom/core/store/json_store.dart';
import 'package:bloom/core/store/library_store.dart' show jsonStoreProvider;
import 'package:bloom/core/store/settings_store.dart';
import 'package:bloom/features/customization/custom_store.dart';
import 'package:bloom/features/customization/media_store.dart';
import 'package:bloom/features/customization/presets_file.dart';
import 'package:bloom/features/customization/presets_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container([JsonStore? store]) {
  final c = ProviderContainer(
    overrides: [
      jsonStoreProvider.overrideWithValue(store ?? JsonStore.memory()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Добавляет картинку ссылкой — единственный путь, которому не нужен диск.
String _add(ProviderContainer c, String url) {
  expect(c.read(mediaLibProvider.notifier).addUrl(url), isTrue);
  return c.read(mediaLibProvider).last.id;
}

void main() {
  group('библиотека', () {
    test('ссылку принимаем, мусор — нет', () {
      final c = _container();
      final lib = c.read(mediaLibProvider.notifier);
      expect(lib.addUrl('https://example.com/a.gif'), isTrue);
      expect(lib.addUrl('ftp://example.com/a.gif'), isFalse);
      expect(lib.addUrl('  '), isFalse);
      expect(c.read(mediaLibProvider), hasLength(1));
      expect(c.read(mediaLibProvider).single.name, 'a.gif');
    });

    test('имя из ссылки не тащит параметры запроса', () {
      expect(urlName('https://e.com/pic.png?w=1&h=2'), 'pic.png');
      expect(urlName('https://e.com/'), 'image');
    });

    test('размытие и затемнение живут у картинки и переживают перезапуск', () {
      final store = JsonStore.memory();
      final c = _container(store);
      final id = _add(c, 'https://e.com/a.jpg');
      c.read(mediaLibProvider.notifier).setBlur(id, 40);
      c.read(mediaLibProvider.notifier).setDim(id, 200); // выше потолка
      final fresh = _container(store);
      final item = fresh.read(mediaLibProvider).single;
      expect(item.blur, 40);
      expect(item.dim, kBgDimMax);
    });

    test('битую запись из файла молча пропускаем', () {
      final store = JsonStore.memory({
        'media': [
          {'id': 'ml1', 'src': 'https://e.com/a.jpg'},
          {'id': 'ml2'}, // без картинки
          'мусор',
        ],
      });
      expect(_container(store).read(mediaLibProvider), hasLength(1));
    });
  });

  group('контексты', () {
    test('контекст держит одну картинку', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      final b = _add(c, 'https://e.com/b.jpg');
      final custom = c.read(customProvider.notifier);
      custom.toggle(CustomCtx.bg, a, true);
      custom.toggle(CustomCtx.bg, b, true);
      expect(c.read(customProvider).bg, b);
      // Выключение чужой картинки не снимает стоящую.
      custom.toggle(CustomCtx.bg, a, false);
      expect(c.read(customProvider).bg, b);
      custom.toggle(CustomCtx.bg, b, false);
      expect(c.read(customProvider).bg, isNull);
    });

    test('одна картинка может стоять сразу в двух контекстах', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      c.read(customProvider.notifier).toggle(CustomCtx.slider, a, true);
      expect(c.read(customSrcProvider(CustomCtx.bg)), 'https://e.com/a.jpg');
      expect(
        c.read(customSrcProvider(CustomCtx.slider)),
        'https://e.com/a.jpg',
      );
      expect(c.read(customSrcProvider(CustomCtx.cover)), isNull);
    });

    test('значки на плитке показывают занятые контексты по порядку', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      final b = _add(c, 'https://e.com/b.jpg');
      expect(c.read(mediaUsageProvider(a)), isEmpty);

      c.read(customProvider.notifier).toggle(CustomCtx.slider, a, true);
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      // Порядок — как у тумблеров на странице картинки, а не как включали.
      expect(c.read(mediaUsageProvider(a)), [CustomCtx.bg, CustomCtx.slider]);
      expect(c.read(mediaUsageProvider(b)), isEmpty);

      // Картинку выбили из контекста другой — значок обязан уйти.
      c.read(customProvider.notifier).toggle(CustomCtx.bg, b, true);
      expect(c.read(mediaUsageProvider(a)), [CustomCtx.slider]);
      expect(c.read(mediaUsageProvider(b)), [CustomCtx.bg]);
    });

    test('удаление картинки чистит контексты и пресеты', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      final b = _add(c, 'https://e.com/b.jpg');
      final custom = c.read(customProvider.notifier);
      custom.toggle(CustomCtx.bg, a, true);
      custom.toggle(CustomCtx.cover, b, true);
      expect(c.read(presetsProvider.notifier).save('оба'), isNotNull);

      removeMedia(c.read, a);
      expect(c.read(customProvider).bg, isNull);
      expect(c.read(customProvider).cover, b);
      expect(c.read(mediaLibProvider), hasLength(1));
      // Пресет остался, но уже без удалённой картинки.
      expect(c.read(presetsProvider).single.bg, isNull);
      expect(c.read(presetsProvider).single.cover, b);

      // Удалили последнюю — опустевший пресет уходит целиком.
      removeMedia(c.read, b);
      expect(c.read(presetsProvider), isEmpty);
      expect(c.read(mediaLibProvider), isEmpty);
    });
  });

  group('пресеты', () {
    test('пустые контексты сохранять нечего', () {
      final c = _container();
      expect(c.read(presetsProvider.notifier).save('пусто'), isNull);
      expect(c.read(presetsProvider), isEmpty);
    });

    test('применение ставит заданные контексты и не трогает пустые', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      final b = _add(c, 'https://e.com/b.jpg');
      final custom = c.read(customProvider.notifier);
      custom.toggle(CustomCtx.bg, a, true);
      final preset = c.read(presetsProvider.notifier).save('только фон')!;

      custom.set(CustomCtx.bg, null);
      custom.toggle(CustomCtx.cover, b, true);
      c.read(presetsProvider.notifier).apply(preset.id);
      expect(c.read(customProvider).bg, a);
      // Обложки в пресете не было — её оставили как есть, как на ПК.
      expect(c.read(customProvider).cover, b);
    });

    test('лимит пресетов', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      for (var i = 0; i < kPresetsLimit; i++) {
        expect(c.read(presetsProvider.notifier).save('p$i'), isNotNull);
      }
      expect(c.read(presetsProvider.notifier).save('лишний'), isNull);
      expect(c.read(presetsProvider), hasLength(kPresetsLimit));
    });
  });

  group('файл пресетов', () {
    test(
      'круг выгрузка → загрузка сохраняет картинки и не плодит дубли',
      () async {
        final source = _container();
        final a = _add(source, 'https://e.com/a.jpg');
        final b = _add(source, 'https://e.com/b.gif');
        source.read(mediaLibProvider.notifier).setBlur(a, 24);
        source.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
        source.read(customProvider.notifier).toggle(CustomCtx.slider, b, true);
        final preset = source.read(presetsProvider.notifier).save('мой')!;

        final content = await encodePresets([
          preset,
        ], source.read(mediaLibProvider));

        // Чужое устройство: библиотека пуста.
        final target = _container();
        expect(await importPresets(target.read, content), 1);
        expect(target.read(mediaLibProvider), hasLength(2));
        final imported = target.read(presetsProvider).single;
        expect(imported.name, 'мой');
        // Размытие приехало вместе с картинкой фона, а не потерялось.
        expect(
          target.read(mediaLibProvider.notifier).byId(imported.bg)!.blur,
          24,
        );
        expect(
          target.read(mediaLibProvider.notifier).byId(imported.slider)!.src,
          'https://e.com/b.gif',
        );

        // Повторный импорт того же файла: пресет второй, а картинки те же.
        expect(await importPresets(target.read, content), 1);
        expect(target.read(mediaLibProvider), hasLength(2));
        expect(target.read(presetsProvider), hasLength(2));
      },
    );

    test('чужой и битый файл не проходят', () async {
      final c = _container();
      expect(decodePresets('не json'), isEmpty);
      expect(decodePresets('{"kind":"чужое"}'), isEmpty);
      // Пресет без единой картинки — не пресет.
      expect(decodePresets('[{"name":"пусто"}]'), isEmpty);
      expect(await importPresets(c.read, 'не json'), 0);
    });

    test('голый массив пресетов тоже читаем', () {
      final parsed = decodePresets(
        '[{"name":"a","bg":"https://e.com/a.jpg","dim":50}]',
      );
      expect(parsed, hasLength(1));
      expect(parsed.single.dim, 50);
    });

    test('имя файла чистится от запрещённых символов', () {
      // Пробелы остаются — они в именах файлов законны, как и на ПК.
      expect(presetFileName('лето/2026: ночь'), 'лето_2026_ ночь.bloompresets');
      expect(presetFileName('   '), 'preset.bloompresets');
    });
  });

  group('фон', () {
    test('своя картинка важнее обложки трека', () {
      final c = _container();
      final a = _add(c, 'https://e.com/a.jpg');
      c.read(settingsProvider.notifier).setCoverAsBg(true);
      c.read(customProvider.notifier).toggle(CustomCtx.bg, a, true);
      c.read(mediaLibProvider.notifier).setDim(a, 30);

      final bg = c.read(customItemProvider(CustomCtx.bg));
      expect(bg!.src, 'https://e.com/a.jpg');
      expect(bg.dim, 30);
    });

    test('«обложка как фон» переживает перезапуск', () {
      final store = JsonStore.memory();
      _container(store).read(settingsProvider.notifier).setCoverAsBg(true);
      expect(_container(store).read(settingsProvider).coverAsBg, isTrue);
    });
  });
}
