/// База для тестов — в памяти, одна на хранилище настроек: новый контейнер
/// поверх того же [JsonStore] видит те же данные, то есть «перезапуск»
/// приложения в тесте проходит и для базы.
library;

import 'package:bloom/core/db/db.dart';

final Expando<BloomDb> _dbs = Expando('testDb');

BloomDb testDb(Object store) => _dbs[store] ??= BloomDb.memory();
