/// Центр уведомлений — история событий за сессию. Порт десктопных
/// `shared/ui/notificationsStore.ts` и `NotifBell.tsx`: вход — колокольчик в
/// шапке главной, содержимое — те же события, что кладёт в историю ПК.
///
/// В отличие от тостов (`bloom_toast.dart`), которые гаснут через пару секунд,
/// уведомление остаётся в списке — но **только пока живёт процесс**: на диск
/// ничего не пишем, как и на десктопе (там список чистится закрытием окна).
/// Тост при этом остаётся как был, уведомление лишь ДУБЛИРУЕТ событие в
/// историю.
///
/// Два отличия от ПК, оба вынужденные:
/// - вида `update` нет — обновлялки в мобилке нет вовсе, и звать его нечем;
/// - кнопки-действия в карточке нет по той же причине: единственным её
///   пользователем на ПК был апдейтер («Подробнее»).
///
/// Заголовок хранится КЛЮЧОМ ([NotifTitle]), а не готовой строкой: смена языка
/// обязана перерисовать уже накопленный список (на ПК ровно так же —
/// `titleKey` релокализуется при показе панели). Тело, наоборот, снимок на
/// момент события: там имя трека или причина отказа, и пересчитать его потом
/// уже не из чего.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../core/log/bloom_log.dart';

/// Вид уведомления: от него зависят значок и его цвет.
enum NotifKind { info, success, error }

/// Заголовок уведомления. Enum, а не строка, — ради релокализации; порядок и
/// состав повторяют десктопные ключи `notif.*.title`.
enum NotifTitle {
  /// `notif.trackDl.title` — трек сохранён файлом.
  trackDownloaded,

  /// `notif.dlError.title` — сохранить файлом не удалось.
  downloadError,

  /// `notif.offline.title` — трек лёг в офлайн-кеш.
  offlineReady,

  /// `notif.offlineError.title` — офлайн-копию скачать не удалось.
  offlineError,

  /// `notif.trackUnavailable.title` — трек не заиграл.
  trackUnavailable,
}

/// Сколько уведомлений держим (десктопный `MAX`).
const int kNotifMax = 50;

/// Часы центра. Отдельным провайдером — чтобы тесты могли поставить своё время
/// (тот же приём, что у `sleepClockProvider`).
final notifClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

class NotifItem {
  const NotifItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.ts,
    this.read = false,
  });

  final String id;
  final NotifKind kind;
  final NotifTitle title;

  /// Готовый текст тела — снимок на момент события.
  final String body;

  /// Когда случилось.
  final DateTime ts;

  final bool read;

  NotifItem copyWith({bool? read}) => NotifItem(
    id: id,
    kind: kind,
    title: title,
    body: body,
    ts: ts,
    read: read ?? this.read,
  );
}

final notifCenterProvider = NotifierProvider<NotifCenter, List<NotifItem>>(
  NotifCenter.new,
);

/// Непрочитанные — бейдж на колокольчике.
final notifUnreadProvider = Provider<int>(
  (ref) => ref.watch(notifCenterProvider).where((n) => !n.read).length,
);

class NotifCenter extends Notifier<List<NotifItem>> {
  @override
  List<NotifItem> build() => const [];

  /// Счётчик в id: на ПК вторую половину id даёт `Math.random()`, а у нас два
  /// события в одну миллисекунду — обычное дело (загрузка списка), и на голом
  /// времени id повторились бы.
  int _seq = 0;

  /// Добавить событие в историю. Свежие сверху, лишние с хвоста отваливаются.
  void add({
    required NotifKind kind,
    required NotifTitle title,
    String body = '',
  }) {
    final now = ref.read(notifClockProvider)();
    final item = NotifItem(
      id: '${now.millisecondsSinceEpoch}-${_seq++}',
      kind: kind,
      title: title,
      body: body,
      ts: now,
    );
    state = [item, ...state].take(kNotifMax).toList();
    // Заодно в журнал работы: список уведомлений живёт только эту сессию, а
    // «почему трек не скачался» спрашивают уже после перезапуска.
    BloomLog.instance.add(
      kind == NotifKind.error ? LogLevel.error : LogLevel.info,
      'notif',
      body.isEmpty ? title.name : '${title.name}: $body',
    );
  }

  /// Открытие списка = всё прочитано (бейдж гаснет).
  void markAllRead() {
    if (state.every((n) => n.read)) return; // нечего обновлять
    state = [
      for (final n in state)
        if (n.read) n else n.copyWith(read: true),
    ];
  }

  void clear() {
    if (state.isEmpty) return;
    state = const [];
  }
}

/// Заголовок фразой. Живёт здесь, рядом с самим ключом: только так видно, что
/// новый вид уведомления обязан получить перевод.
String notifTitleText(AppLocalizations l, NotifTitle title) => switch (title) {
  NotifTitle.trackDownloaded => l.notifTrackDownloaded,
  NotifTitle.downloadError => l.notifDownloadError,
  NotifTitle.offlineReady => l.notifOfflineReady,
  NotifTitle.offlineError => l.notifOfflineError,
  NotifTitle.trackUnavailable => l.notifTrackUnavailable,
};
