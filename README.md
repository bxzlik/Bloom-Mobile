<div align="center">

<img src="assets/brand/bloom_mark.png" width="96" height="96" alt="Bloom" />

# Bloom Mobile

**Music from every source in one player.**

Android and iOS: SoundCloud, Yandex Music
and YouTube Music in a single app

[**📦 Releases**](https://github.com/bxzlik/Bloom-Mobile/releases) · [**🖥 Desktop**](https://github.com/bxzlik/Bloom) · [**🌐 Website**](https://bloom-site-x.vercel.app/)

**English** · [Русский](README.ru.md)

</div>

## 💿 Platforms

| Platform | Notes |
| --- | --- |
| 🟠 **SoundCloud** | Native streaming |
| 🔴 **YouTube Music** | Not started |
| 🟡 **Yandex Music** | Not started |

Providers are rewritten in Dart — the desktop Rust is not reused. The comments
in [`src-tauri/src/*.rs`](https://github.com/bxzlik/Bloom) remain the spec: they
document the whole reverse engineering of each platform.

## 🚀 Development

```bash
flutter pub get

flutter run -d <device>
flutter test                  # mapping, no network
dart run tool/sc_smoke.dart   # live smoke against the SoundCloud api-v2

flutter build apk --release   # android
flutter build ios --release   # ios, needs macOS
```

Requires [Flutter](https://docs.flutter.dev/get-started/install) 3.41+.

Releases are built by GitHub Actions: push a `v1.2.3` tag and the APK and the
unsigned IPA land in a release. Signing keys and secrets are described in the
comments of [`.github/workflows/release.yml`](.github/workflows/release.yml).

## 📄 License

[MIT](LICENSE)
