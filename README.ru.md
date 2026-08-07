<div align="center">

<img src="assets/brand/bloom_mark.png" width="96" height="96" alt="Bloom" />

# Bloom Mobile

**Музыка из всех источников в одном плеере.**

Android и iOS: SoundCloud, Yandex Music
и YouTube Music в одном приложении

[**📦 Релизы**](https://github.com/bxzlik/Bloom-Mobile/releases) · [**🖥 Десктоп**](https://github.com/bxzlik/Bloom) · [**🌐 Сайт**](https://bloom-site-x.vercel.app/)

[English](README.md) · **Русский**

</div>

## 💿 Площадки

| Площадка | Примечания |
| --- | --- |
| 🟠 **SoundCloud** | Нативное воспроизведение |
| 🔴 **YouTube Music** | Не начат |
| 🟡 **Yandex Music** | Не начат |

Провайдеры пишутся на Dart заново, десктопный Rust не переиспользуется.
Комментарии в [`src-tauri/src/*.rs`](https://github.com/bxzlik/Bloom) остаются
спецификацией: там описан весь реверс-инжиниринг площадок.

## 🚀 Разработка

```bash
flutter pub get

flutter run -d <device>
flutter test                  # маппинг без сети
dart run tool/sc_smoke.dart   # живой smoke против api-v2 SoundCloud

flutter build apk --release   # android
flutter build ios --release   # ios, нужен macOS
```

Требуется [Flutter](https://docs.flutter.dev/get-started/install) 3.41+.

Релизы собирает GitHub Actions: пушнуть тег `v1.2.3` — APK и неподписанный IPA
лягут в релиз. Ключ подписи и секреты описаны в комментариях
[`.github/workflows/release.yml`](.github/workflows/release.yml).

## 📄 License

[MIT](LICENSE)
