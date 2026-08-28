/// Ошибка воспроизведения на языке пользователя.
///
/// Провайдеры бросают не текст, а КОД словаря (`search.err.*`, `sc.err.*`,
/// `ym.err.*`, `ytm.err.*`) — ровно как на десктопе, где их разворачивает
/// `i18nT`. Плеер кладёт код в [PlaybackState.error] как есть (локаль на момент
/// падения могла быть другой, чем на момент показа), а разворачивается он здесь,
/// при отрисовке — иначе под названием трека стоит «search.err.drm».
///
/// Незнакомый код показываем как есть: это либо текст самой площадки
/// (`SC API error`, сообщение из `errors[]`), либо уже готовая фраза
/// (`LocalFileGone`).
library;

import '../../core/l10n/l10n.dart';
import '../settings/ui/yandex_screen.dart' show describeYmError;

/// Код ошибки из брошенного исключения.
///
/// `StateError` подмешивает к сообщению своё «Bad state: » — до словаря должен
/// доехать голый код, иначе `search.err.noStream` не совпадёт ни с чем.
String playErrorCode(Object err) {
  const badState = 'Bad state: ';
  final s = err.toString();
  return s.startsWith(badState) ? s.substring(badState.length) : s;
}

/// Трек не заиграл из-за DRM. Как `/DRM/i.test(msg)` на ПК: коды у площадок
/// разные, а тост нужен один.
bool isDrmError(String code) => code.toLowerCase().contains('drm');

/// Код → фраза.
String describePlayError(AppLocalizations l, String code) => switch (code) {
  'search.err.drm' || 'sc.err.drm' => l.errDrm,
  'search.err.noStream' || 'sc.err.noStream' || 'sc.err.noCdn' => l.errNoStream,
  'sc.err.unavailable' => l.errScUnavailable,
  'sc.err.forbidden' => l.errScForbidden,
  'sc.err.clientIdInvalid' || 'sc.err.clientIdExpired' => l.errScClientId,
  'ytm.err.noAudio' => l.errYtmNoAudio,
  'ytm.err.network' => l.errYtmNetwork,
  'ytm.err.trackNotFound' || 'ym.err.trackNotFound' => l.errTrackNotFound,
  _ when code.startsWith('ym.err.') => describeYmError(l, code),
  _ => code,
};
