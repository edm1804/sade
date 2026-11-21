<p align="center">
  <img src="assets/sade.png" width="104" alt="Sade icon">
  <img src="assets/sade-tuval.png" width="104" alt="Sade Tuval icon">
</p>

<h1 align="center">Sade & Sade Tuval</h1>

<p align="center">A calm macOS workspace for tasks, planners, voice notes, and connected ideas.</p>

<p align="center">
  <a href="https://github.com/edm1804/sade/releases">Download</a> ·
  <a href="#english">English</a> ·
  <a href="#türkçe">Türkçe</a> ·
  <a href="https://github.com/edm1804/sade/issues">Feedback</a>
</p>

**Version 1.0.0 · macOS 14+ · Apple Silicon · Türkçe / English**

## English

Two independent apps in one download. Use Sade to organize your day, Sade Tuval to explore ideas on a freeform canvas, or both together.

### Sade

- Daily task lists and weekly planners.
- Book-style categories with customizable covers, colors, icons, patterns, captions, and bookmarks.
- Reminders, focus timers, subtasks, and voice notes.
- Menu bar status for today’s tasks and upcoming reminders.

### Sade Tuval

- A freeform workspace for headings, text, checklists, tables, project boards, and links to Sade tasks.
- Draggable, resizable blocks with connections between them.
- A collapsible block library, a block editing panel, and a right-click menu.
- Zoom controls and optional grid snapping.

### Install

1. Open [Releases](https://github.com/edm1804/sade/releases).
2. Download `Sade-1.0.0-macOS-arm64.zip` from the **Assets** section.
3. Extract the archive and move either or both apps to Applications.
4. Open the app you want to use. Sade is needed to open linked tasks from Tuval.

This build targets **macOS 14 or later on Apple Silicon**. Intel, Windows, Android, and iOS builds are not included.

**Distribution status:** The initial package is ad hoc signed and has not been notarized by Apple. macOS may block or warn about it. Developer ID signing and notarization are still pending.

### Language, appearance, and updates

Open **Settings** with `⌘,` to choose System, Türkçe, or English and automatic, warm light, or dark appearance. Each app remembers its own preferences. Changing the interface language keeps your task names, category names, and written content unchanged.

Automatic update checks use `edm1804/sade`. They run on launch or activation, at most once a day, and can be disabled in Settings. An available update opens the release page; downloading and installing remain manual.

### Your data

Tasks, canvases, and voice notes are stored locally in:

```text
~/Library/Application Support/Sade/
```

Settings and planner covers are stored in macOS preferences. There is no cloud sync in this release. Update checks contact GitHub without sending your task, canvas, or voice-note content. Notification and microphone permissions are requested when those features are used.

## Türkçe

Tek indirmede iki bağımsız uygulama. Gününü **Sade** ile planla, fikirlerini **Sade Tuval** üzerinde bir araya getir. İstersen yalnızca ihtiyacın olan uygulamayı kullan.

### Sade

- Günlük görev listesi ve haftalık ajanda.
- Renk, simge, desen, kısa yazı ve ayraçla kişiselleştirilebilen kitap kapaklı kategoriler.
- Hatırlatmalar, odak zamanlayıcısı, alt görevler ve sesli notlar.
- Bugünkü işler ve yaklaşan hatırlatmalar için menü çubuğu durumu.

### Sade Tuval

- Başlık, metin, kontrol listesi, tablo, proje panosu ve Sade görev bağlantıları için serbest çalışma alanı.
- Sürüklenebilen, boyutlandırılabilen ve birbirine bağlanabilen bloklar.
- Gizlenebilir ekleme ve düzenleme paneli, sağ tık menüsü, yakınlaştırma ve isteğe bağlı ızgaraya hizalama.

### Kurulum

1. [Releases](https://github.com/edm1804/sade/releases) sayfasını aç.
2. **Assets** bölümünden `Sade-1.0.0-macOS-arm64.zip` dosyasını indir.
3. ZIP’i açıp kullanacağın uygulamaları Uygulamalar klasörüne taşı.
4. Tuval’den bağlı görevleri açmak için Sade’yi de kullan.

Bu paket **Apple Silicon ve macOS 14 veya üzerini** hedefler. Intel Mac, Windows ve mobil sürümler bu pakete dahil değildir.

**Dağıtım durumu:** İlk paket yerel olarak imzalanmıştır; Apple notarization işlemi yapılmamıştır. macOS uygulamayı engelleyebilir veya uyarı gösterebilir. Developer ID imzalama ve notarization hazırlığı henüz tamamlanmamıştır.

### Ayarlar ve kayıtlar

`⌘,` ile Ayarlar’ı açıp Sistem / Türkçe / English dilini ve otomatik / sıcak açık / koyu temayı seçebilirsin. Her uygulama kendi seçimini hatırlar. Görev, kategori ve kapak yazıların dil değişince yeniden adlandırılmaz.

Güncellemeler `edm1804/sade` üzerinden açılışta veya uygulamaya dönüldüğünde günde en fazla bir kez denetlenir. Otomatik kontrol kapatılabilir; indirme ve kurulum sana aittir.

Görevler, tuvaller ve sesli notlar Mac’indeki `~/Library/Application Support/Sade/` klasöründe; tercihler ve ajanda kapakları macOS ayar kayıtlarında tutulur. Bu sürümde bulut eşitleme yoktur. Güncelleme kontrolü GitHub’a görev, tuval veya ses içeriklerini göndermez.

## Build from source

The apps are written in SwiftUI and AppKit. No third-party packages are required. An Xcode project is not included in this release.

The build script uses Command Line Tools at `/Library/Developer/CommandLineTools` and defaults to `MacOSX26.5.sdk`. Install compatible tools and set `SADE_SDK_PATH` if your SDK is located elsewhere.

From the source directory:

```sh
zsh build.sh build
```

Output: `build/Sade.app` and `build/Sade Tuval.app`. The script produces ad hoc signatures.

| Source | Purpose |
| --- | --- |
| `Sade.swift`, `Planner.swift`, `CategoryBooks.swift` | Tasks, planners, and covers |
| `CanvasApp.swift`, `Workspace.swift`, `WorkspaceCanvas.swift`, `CanvasInspector.swift` | Canvas app, models, and editing |
| `TaskModels.swift`, `Companion.swift` | Shared task models and app links |
| `SharedStyle.swift`, `StartupSplash.swift` | Appearance and startup presentation |
| `Localization.swift`, `Resources/` | Language selection and translations |
| `Settings.swift`, `Updates.swift` | Settings and GitHub release checks |

For translation changes, preserve `%@` placeholders. User-written content and stored identifiers must not be translated.

## Feedback

Report problems or suggest improvements in [Issues](https://github.com/edm1804/sade/issues). Include your macOS version, app version, and steps to reproduce. Remove personal content from screenshots and logs before sharing them.

## License

No open-source license has been selected for this release.
