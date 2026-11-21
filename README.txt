Sade ve Sade Tuval

İlk yayın sürümü: 1.0.0

Birlikte paketlenen iki bağımsız macOS uygulaması.

Sade
Günlük görevler, kitap kapaklı kategoriler, haftalık ajandalar, yerel sesli notlar, zamanlayıcılar ve menü çubuğu.

Sade Tuval
Serbest yerleşimli bloklar, ok bağlantıları, boyutlandırma, ekleme paneli, seçili blok düzenleyicisi ve isteğe bağlı ızgara hizalaması.

Dil desteği
Her iki uygulama Türkçe ve İngilizce sunar. Ayarlar → Dil bölümünde Sistem, Türkçe veya English seçilebilir. Sistem seçimi desteklenen Mac dil tercihini kullanır; eşleşme yoksa İngilizce açılır. Dil değişikliği anında uygulanır ve iki uygulama kendi tercihini ayrı saklar. Kullanıcının görev, kategori ve kapak metinleri çevrilmez. macOS’un sağladığı menüler ve izin pencereleri sistem dilini izleyebilir.

Gereksinimler
Bu sürüm Apple Silicon Mac için, macOS 14 ve üzeri hedefiyle hazırlanır. Derleme betiği Command Line Tools ve varsayılan olarak MacOSX26.5.sdk kullanır. Farklı kurulu SDK için SADE_SDK_PATH değişkeni ayarlanabilir.

Derleme
Kaynak klasöründe Terminal açıp aşağıdaki komutu çalıştır.

zsh build.sh build

Çıktılar build/Sade.app ve build/Sade Tuval.app olur. Ek paket veya üçüncü taraf bağımlılık gerekmez. Xcode projesi bu sürüme dahil değildir.

Kaynak düzeni
Sade.swift — görev uygulaması, kayıt deposu, menü çubuğu ve görev detayları.
CanvasApp.swift — bağımsız Tuval uygulaması.
TaskModels.swift — ortak görev modeli ve görev bağlantısı adresleri.
Workspace.swift — tuval kayıt modeli ve blok içerikleri.
WorkspaceCanvas.swift — serbest tuval, sürükleme, bağlantı ve boyutlandırma.
CanvasInspector.swift — blok ekleme açıklamaları ve seçili blok özellikleri.
Planner.swift — kurulum ekranı ve haftalık ajanda.
CategoryBooks.swift — kitap kapaklı kategoriler ve kapak kişiselleştirme.
SharedStyle.swift — ortak görünüm, düğmeler ve pencere animasyonu.
Localization.swift — dil seçimi ve arayüz çeviri yardımcısı.
Resources/tr.lproj ve Resources/en.lproj — çeviriler ve mikrofon izin açıklamaları.
Settings.swift — görünüm seçimi ve GitHub sürüm denetimi.
StartupSplash.swift — yalnızca ilk açılışta gösterilen logo penceresi.
Companion.swift — iki uygulama arasında geçiş.
MakeAppIcons.swift — ikonları oluşturan kaynak.
Info.plist ve Tuval-Info.plist — uygulama kimlikleri ve izin açıklamaları.

Kayıtlar
Kullanıcının Library/Application Support/Sade klasöründe tasks.json, workspace.json ve ses kayıtları bulunur. Bunlar kaynak paketine dahil değildir. Uygulama tercihleri macOS UserDefaults içinde tutulur.

GitHub Releases
Bu sürümün etiketi v1.0.0 olmalıdır. Kullanıma hazır iki uygulamayı içeren Sade.zip dosyası Release eki olarak yüklenir. Sonraki sürümlerde her uygulamanın Info.plist sürüm numarası ve sayısal Release etiketi birlikte güncellenir. Ayarlar’a girilen herkese açık GitHub deposundaki en son kararlı Release denetlenir.

Dağıtım durumu
build.sh yerel kullanım için ad hoc imza üretir. Başka kullanıcılara macOS dağıtımı için Developer ID imzalama ve Apple notarization süreci ayrıca hazırlanmalıdır.

Lisans
Bu pakete bir açık kaynak lisansı seçilip eklenmedi. Herkese açık depoya yüklemek, tek başına yeniden kullanım lisansı belirlemez.

Çevirilere katkı
Arayüz anahtarları Türkçe kaynak metinleridir. Resources altındaki Localizable.strings dosyalarında karşılıkları bulunur. %@ yer tutucularının sayısını ve sırasını koru. Dil metinleri L() üzerinden gösterilir; kullanıcı içerikleri ve kayıtlardaki kimlikler bu yardımcıya verilmez. Yeni dil için AppLanguage seçeneklerini, Info.plist dil listesini ve ilgili .lproj klasörünü birlikte güncelle.
