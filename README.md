# Bloom Mobile

Мобильный Bloom (Android / iOS) — Flutter, пакет `com.bxzlik.bloom`.

Провайдеры пишутся на Dart заново, десктопный Rust не переиспользуется:
`c:\bloom\bloom` (репозиторий [bxzlik/Bloom](https://github.com/bxzlik/Bloom))
остаётся источником спецификации — комментарии в `src-tauri/src/*.rs` описывают
весь реверс-инжиниринг площадок.

## Состояние

| Площадка | Статус |
| --- | --- |
| SoundCloud | порт api-v2 готов: поиск, артист, плейлисты, резолв ссылок, стрим |
| YouTube Music | не начат |
| Яндекс.Музыка | не начат |

UI: каркас готов — три таба, миниплеер, полноэкранный плеер с очередью.
Раскладка экранов повторяет присланный референс, вид и цвета — токены
десктопного Bloom (пока одна тема Dark). Содержимое Главной (созвездие «Моя
волна», «Недавние», ленты), Библиотеки и Настроек — впереди.

## Разработка

```sh
flutter pub get
flutter run -d <device>

flutter test                  # маппинг без сети
dart run tool/sc_smoke.dart   # живой smoke против api-v2 SoundCloud
```

`sc_smoke` — порт `sc_smoke` из десктопного `soundcloud.rs`: поиск → стрим →
байты с CDN → артист → резолв. Гонять, когда SoundCloud перестал играть: сразу
видно, протух ли `client_id`.

## Сборки

`.github/workflows/ci.yml` на каждый пуш гоняет `dart format`, `flutter
analyze` и `flutter test`. `.github/workflows/release.yml` собирает
приложения — двумя способами:

- **тег `v1.2.3`** — собирает Android и iOS и выкладывает файлы в GitHub
  Release (версия берётся из тега, номер сборки — счётчик прогонов);
- **кнопка «Run workflow»** на вкладке Actions — просто сборка «посмотреть»,
  файлы лежат артефактами прогона 90 дней. Там же выбирается платформа: минуты
  macOS идут с множителем ×10, гонять их ради правки в Android незачем.

```sh
flutter build apk --release      # android: build/app/outputs/flutter-apk/
flutter build ios --release      # ios: нужен macOS и Xcode
```

**Подпись Android.** Ключ описывается в `android/key.properties` (в git его
нет — см. `android/.gitignore`); файла нет — релиз подписывается отладочным
ключом, как в шаблоне Flutter. Отладочный ключ на каждой машине свой, поэтому
такие APK не ставятся обновлением друг поверх друга. Свой ключ:

```sh
keytool -genkey -v -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

```properties
# android/key.properties — путь считается от папки android/
storeFile=upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

Для CI тот же ключ кладётся в секреты репозитория (Settings → Secrets and
variables → Actions): `ANDROID_KEYSTORE_BASE64` (`base64 -w0
android/upload-keystore.jks`), `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`. Без них сборка не падает, а предупреждает и подписывает
отладочным ключом.

**iOS.** Сертификата разработчика Apple у проекта нет, поэтому CI собирает
`--no-codesign` и пакует `Payload/Runner.app` в `bloom.ipa` руками (Xcode
делает это только при экспорте с подписью). Такой `.ipa` ставится на устройство
после переподписи — Sideloadly, AltStore или Xcode.

## Структура

```
lib/
  core/entities/          общие Track/Artist/Playlist — к ним приводят все
                          площадки (порт src/entities/*)
  core/providers/         контракт MusicProvider и реестр (порт
                          features/providers/model/*)
  app/theme/              порт themeStore.ts + root.css: тема = три цвета,
                          остальное — формулы (BloomTokens как ThemeExtension)
  app/providers.dart      регистрация площадок (аналог bootstrap в App.tsx)
  app/router.dart         go_router + StatefulShellRoute (три таба)
  app/shell.dart          таб-бар и миниплеер под контентом
  providers/soundcloud/   порт src-tauri/src/soundcloud.rs (функция-в-функцию)
                          + sc_provider.dart: реализация контракта
  features/player/        очередь, авто-переход, мини и полный плеер
  core/store/            файловое JSON-хранилище + библиотека и настройки
  features/home/          шапка из референса (созвездие и ленты — впереди)
  features/search/        своя страница: чипы-фильтры и выдача секциями
  features/library/       разделы, плейлисты, подписки, импорт по ссылке
  features/settings/      группы разделов; работают «Интерфейс» и SoundCloud
  shared/                 круглые кнопки, обложки, форматирование
assets/fonts/Inter.ttf    вариативный Inter (--font десктопа)
assets/brand/             знак bloom (8-лучевая звезда)
assets/icons/             Solar-SVG там, где глиф в шрифте нарисован не тем
assets/platform/          логотипы площадок и сервисов из десктопного Bloom
tool/sc_smoke.dart        сетевой smoke
```

Токены темы покрыты тестом (`test/theme_tokens_test.dart`): производные тона
сверены с числами из комментариев `themeStore.ts`.
