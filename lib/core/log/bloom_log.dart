/// Журнал работы приложения — «Настройки → Система → Логи».
///
/// На десктопе логи пишет Rust (`tracing` в файл, команды `read_logs` /
/// `export_logs` / `clear_logs`); в мобилке своего журнала не было вовсе, и
/// диагностировать «у меня трек не играет» было нечем. Здесь — самое простое,
/// что закрывает ту же задачу.
///
/// Устройство:
///
/// - в памяти кольцевой буфер на [kLogMax] записей — старое вытесняется;
/// - на диск пишется ВЕСЬ буфер целиком (`logs/bloom.log`), отложенно, как в
///   `JsonStore`. Дописыванием файл рос бы без края, а чистить его по размеру
///   значило бы городить ротацию — при переписывании кольца размер файла
///   ограничен самим кольцом;
/// - при старте файл читается обратно: журнал должен переживать перезапуск,
///   иначе от падения в нём не осталось бы ни строчки.
///
/// Запись строкой одна и та же в файле и на экране, поэтому многострочное
/// (стек ошибки) складывается в одну строку — иначе разобрать файл обратно
/// было бы нечем.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../store/app_dirs.dart';

/// Сколько записей держим. 500 строк — это единицы сотен килобайт и заведомо
/// больше, чем нужно, чтобы увидеть, что случилось перед сбоем.
const int kLogMax = 500;

/// Сколько ждём после записи, прежде чем переписать файл. Ошибки любят идти
/// пачками (сеть отвалилась — три площадки подряд), и писать файл на каждую
/// незачем.
const Duration _flushDelay = Duration(seconds: 2);

enum LogLevel { info, warn, error }

class LogEntry {
  const LogEntry(this.at, this.level, this.tag, this.message);

  final DateTime at;
  final LogLevel level;

  /// Откуда запись: `player`, `offline`, `flutter`… Показывается в строке и
  /// помогает искать глазами.
  final String tag;
  final String message;

  /// `2026-08-20 14:03:11 ERROR [player] нет провайдера для xx`
  String format() =>
      '${_stamp(at)} ${level.name.toUpperCase().padRight(5)} [$tag] $message';

  /// Разбор строки из файла. `null` — строка чужая или битая: журнал не тот
  /// файл, ради которого стоит падать, такие строки просто пропускаем.
  static LogEntry? parse(String line) {
    final m = _lineRe.firstMatch(line);
    if (m == null) return null;
    final at = DateTime.tryParse(m.group(1)!);
    if (at == null) return null;
    final level = LogLevel.values.firstWhere(
      (l) => l.name == m.group(2)!.toLowerCase(),
      orElse: () => LogLevel.info,
    );
    return LogEntry(at, level, m.group(3)!, m.group(4)!);
  }

  static final RegExp _lineRe = RegExp(
    r'^(\S+ \S+) (INFO |WARN |ERROR) \[([^\]]*)\] (.*)$',
  );

  static String _stamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}

class BloomLog {
  BloomLog._();

  /// Журнал один на процесс: писать в него зовут откуда угодно, в том числе из
  /// обработчика необработанных ошибок, где ни `ref`, ни контекста нет.
  static final BloomLog instance = BloomLog._();

  final List<LogEntry> _entries = [];
  File? _file;
  Timer? _debounce;

  /// Записи от старых к новым. Копия: список живой и меняется под ногами у
  /// экрана.
  List<LogEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;
  int get length => _entries.length;

  /// Сколько записей сейчас — для подписи «Настройки → Система → Журнал
  /// работы».
  ///
  /// Просто числом это не работает: страница журнала лежит ПОВЕРХ «Системы»
  /// (вложенный маршрут), та остаётся в стопке живой и после возврата сама не
  /// перестраивается — подпись так и держала бы число, снятое при открытии
  /// экрана, хотя журнал уже очищен.
  final ValueNotifier<int> count = ValueNotifier(0);

  /// Поднять журнал: прочитать файл прошлых запусков. Зовётся из `main()` до
  /// первого кадра, как и остальные хранилища.
  Future<void> open() async {
    try {
      final dir = Directory('${(await appPrivateDir()).path}/logs');
      if (!dir.existsSync()) await dir.create(recursive: true);
      final file = File('${dir.path}/bloom.log');
      _file = file;
      if (!file.existsSync()) return;
      final lines = await file.readAsLines();
      for (final line in lines) {
        final entry = LogEntry.parse(line);
        if (entry != null) _entries.add(entry);
      }
      _trim();
    } catch (_) {
      // Нет места, нет прав, битый файл — журнал живёт в памяти. Падать из-за
      // диагностики нельзя: она сама ничего не решает.
    }
    _bump();
  }

  void add(LogLevel level, String tag, String message) {
    _entries.add(LogEntry(DateTime.now(), level, tag, _flatten(message)));
    _trim();
    _schedule();
    _bump();
  }

  void info(String tag, String message) => add(LogLevel.info, tag, message);
  void warn(String tag, String message) => add(LogLevel.warn, tag, message);

  /// Ошибка с необязательной причиной: `сообщение — Exception: …`.
  void error(String tag, String message, [Object? cause]) =>
      add(LogLevel.error, tag, cause == null ? message : '$message — $cause');

  /// Весь журнал текстом — экран просмотра, копирование и выгрузка в файл.
  String text() => _entries.map((e) => e.format()).join('\n');

  Future<void> clear() async {
    _entries.clear();
    _bump();
    _debounce?.cancel();
    _debounce = null;
    try {
      final file = _file;
      if (file != null && file.existsSync()) await file.delete();
    } catch (_) {
      // Файл не удалился — в памяти журнал уже пуст, следующая запись
      // перепишет его целиком.
    }
  }

  /// Записать немедленно (тесты, уход приложения в фон).
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    final file = _file;
    if (file == null) return;
    try {
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(text(), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // Нет места/прав — журнал остаётся только в памяти.
    }
  }

  void _schedule() {
    // Журнала на диске нет (тесты, десктоп) — писать нечего и таймер заводить
    // незачем: висящий `Timer` роняет виджет-тесты как «утечку».
    if (_file == null) return;
    _debounce?.cancel();
    _debounce = Timer(_flushDelay, flush);
  }

  /// Сообщить подписчикам новое число записей.
  ///
  /// Через микрозадачу, а не сразу: запись в журнал прилетает и из
  /// обработчика необработанных ошибок, а тот срабатывает в том числе посреди
  /// построения кадра — правка [count] оттуда роняла бы слушателя жалобой на
  /// `setState` во время build. Микрозадача выполняется уже после кадра.
  void _bump() {
    if (count.value == _entries.length) return;
    scheduleMicrotask(() => count.value = _entries.length);
  }

  void _trim() {
    if (_entries.length <= kLogMax) return;
    _entries.removeRange(0, _entries.length - kLogMax);
  }

  /// Одна запись — одна строка: переносы схлопываем, длинное режем. Стек
  /// ошибки целиком в журнал не нужен, а разбор файла держится на построчном
  /// формате.
  static String _flatten(String message) {
    final one = message.replaceAll(RegExp(r'\s*\n+\s*'), ' · ').trim();
    return one.length <= 500 ? one : '${one.substring(0, 500)}…';
  }
}

void logInfo(String tag, String message) =>
    BloomLog.instance.info(tag, message);

void logWarn(String tag, String message) =>
    BloomLog.instance.warn(tag, message);

void logError(String tag, String message, [Object? cause]) =>
    BloomLog.instance.error(tag, message, cause);
