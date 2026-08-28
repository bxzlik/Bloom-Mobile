/// Ошибка воспроизведения: код → фраза.
///
/// Проверяем то, что ломается тихо. Провайдеры бросают КОДЫ словаря, а под
/// названием трека в плеере стоит текст — промах здесь показывает человеку
/// «search.err.drm» вместо «Трек защищён DRM». Плюс `StateError`, который
/// подмешивает к сообщению своё «Bad state: » и не даёт коду совпасть.
library;

import 'package:bloom/core/l10n/l10n.dart';
import 'package:bloom/features/player/play_error.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocalizations ru;

  setUpAll(() async {
    ru = await AppLocalizations.delegate.load(const Locale('ru'));
  });

  group('код из исключения', () {
    test('«Bad state:» от StateError до словаря не доезжает', () {
      expect(
        playErrorCode(StateError('search.err.noStream')),
        'search.err.noStream',
      );
    });

    test('своё исключение площадки отдаёт голый код', () {
      expect(playErrorCode(const _Code('search.err.drm')), 'search.err.drm');
    });
  });

  group('DRM', () {
    test('коды площадок разные, признак один', () {
      expect(isDrmError('search.err.drm'), isTrue);
      expect(isDrmError('sc.err.drm'), isTrue);
      expect(isDrmError('search.err.noStream'), isFalse);
    });
  });

  group('фраза', () {
    test('знакомый код разворачивается', () {
      expect(describePlayError(ru, 'search.err.drm'), ru.errDrm);
      expect(describePlayError(ru, 'sc.err.drm'), ru.errDrm);
      expect(describePlayError(ru, 'ytm.err.noAudio'), ru.errYtmNoAudio);
    });

    test('коды Яндекса идут в свой словарь, а не мимо', () {
      expect(describePlayError(ru, 'ym.err.needPlus'), ru.ymErrNeedPlus);
    });

    test('незнакомое — текст самой площадки, показываем как есть', () {
      expect(describePlayError(ru, 'SC API error'), 'SC API error');
    });
  });
}

/// Исключение площадки: `toString` — сам код (как `ScException`).
class _Code implements Exception {
  const _Code(this.code);

  final String code;

  @override
  String toString() => code;
}
