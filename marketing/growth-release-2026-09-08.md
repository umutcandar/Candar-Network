# Candar Network — 8 Eylül 2026 büyüme güncellemesi

Durum: Kullanıcının 8 Eylül yayın onayıyla web güncellemesi candarnetwork.com üzerinde yayınlandı. Sonraki tanıtım aşamasında App Store İngilizce Promotional Text kaydedildi, editör adaylığı ve ücretsiz dizin başvuruları gönderildi; ayrıntılar [ücretsiz tanıtım kaydında](free-promotion-research-2026-09-08.md). Firebase Functions ve yeni mobil paket yayınlanmadı; mobil kaynaklar yerel doğrulamadan geçti. Güncel özel mağaza/GA4 istatistikleri okunmadı; aşağıdaki değişikliklerin indirmeleri artırdığı henüz ölçülmüş değil.

## Sorun ve uygulanan değişiklikler

- Türkçe giriş sayfası, bugünkü ürün faydasından çok erken katılım ve gelecekteki konumu anlatıyordu; bazı bölümler İngilizceydi. Türkçe ve İngilizce ana sayfalar günlük puan, seri ve ilk yedi gün hedefiyle yeniden düzenlendi. Ürün ekranı depodaki mevcut mağaza görselinden alındı ve örnek hesap verisi olarak etiketlendi.
- iOS ziyaretçisi Android mağaza bağlantısının yanında ek bir indirme sayfasına yönleniyordu. Her iki mağaza artık ana ekranda doğrudan erişilebilir. Davetli ziyaretçi önce davet kodunu kopyalayabileceği sayfaya gider.
- `src` alanı `utm_source` değerini eziyor, bağlantıdaki sabit kampanya adı gerçek kampanyayı değiştiriyordu. Tek bir ortak kaynak bilgisi, mevcut oturumda en fazla 30 dakika korunuyor. Yeni kaynak geldiğinde önceki kampanya ve davet bilgisi temizleniyor.
- Türkçe `/download` ve İngilizce `/en/download` hazırlandı. Dil bağlantıları, rehber geçişleri ve indirme düğmeleri kampanya ve davet bilgisini taşıyor.
- Pano yalnız kullanıcı kopyalama düğmesine basınca yazılıyor. Engellenirse elle kopyalama açıklaması gösteriliyor. Kod kayıt alanına yapıştırılabilir; otomatik kurulum sonrası davet tanıma garantisi verilmez.
- Giriş ekranında Google/Apple düğmeleri formun önüne taşındı. Büyük logo bölümü küçültüldü; isteğe bağlı davet alanı açılır hale geldi. Gelen davet kodu alanı otomatik açıyor.
- Eşzamanlı giriş ve şifre sıfırlama istekleri engellendi. Hata sonrası tüm giriş seçenekleri yeniden kullanılabiliyor. Google/Apple başlangıç ve hata olayları mevcut sunucunun kabul ettiği `signup_start` / `signup_error` olaylarına eklendi. İki yeni açıklama 12 dilde mevcut.

## Güncel olarak doğrulanabilen dış sinyal

[Google Play kamuya açık mağaza sayfası](https://play.google.com/store/apps/details?id=com.candarnetwork.app), 8 Eylül 2026 kontrolünde `100+` indirme rozeti, Lifestyle kategorisi ve 22 Ağustos 2026 güncelleme tarihi gösteriyor. Bu rozet son dönemin kesin indirme sayısı veya büyüme oranı değildir. Temmuz raporlarındaki kategori/veri beyanı sorunları güncel sayfada aynı durumda görünmüyor; eski bulgular yeniden uygulanmadı.

## Mağaza metni — yayınlanmamış test adayı

Mevcut mağaza sayfasını değiştirirken aynı anda isim, ikon, ekran görüntüleri ve açıklamayı değiştirmek yerine ilk testte kısa açıklama ve ilk görsel mesajına odaklanın. Aşağıdaki metinler uygulanmış uygulama özellikleriyle sınırlıdır; gelir veya ödül değeri vaat etmez.

| Alan | Türkçe | İngilizce |
| --- | --- | --- |
| Başlık adayı | Candar: Günlük Seri ve AI | Candar: Daily Streaks & AI |
| Kısa açıklama | Günlük puanını topla, 7 günlük serini başlat ve Candar AI’ı keşfet. | Collect daily points, build a 7-day streak, and explore Candar AI. |
| İlk ekran başlığı | İlk 7 günlük serini başlat | Start your first 7-day streak |
| İkinci ekran başlığı | Her gün ilerlemeni gör | See your progress every day |
| Üçüncü ekran başlığı | Arkadaşlarınla birlikte ilerle | Make progress with friends |

Türkçe açıklama başlangıcı:

> İlk hedefin küçük: bugün Candar’a katıl, günlük puanını al ve yarın tekrar gel. Günlük serini takip et, görevleri keşfet ve uygulama içi ilerlemeni görünür kıl. İstersen arkadaşlarını davet et ve Candar AI’a uygulama özelliklerini sor.
>
> Candar ücretsiz indirilebilir. Reklamlar ve isteğe bağlı uygulama içi satın alımlar içerir. Candar puanları yalnızca uygulama içinde kullanılır; nakit veya yatırım getirisi sunmaz.

İngilizce açıklama başlangıcı:

> Start small: join Candar, collect today’s points, and come back tomorrow. Follow your daily streak, explore missions, and see your in-app progress. Invite friends when you want and ask Candar AI about app features.
>
> Candar is free to download. It contains ads and optional in-app purchases. Candar points are for in-app use only and do not provide cash or investment returns.

## Yayından sonra ölçüm

Web kodu olayları mevcut GTM `dataLayer` kuyruğuna gönderir. Bu, GA4'e teslimatın doğrulandığı anlamına gelmez. Yayından önce/sonra mevcut GTM kapsayıcısında ilgili olay etiketleri ve GA4 DebugView kontrol edilmeli. `store_click` bir indirme değildir.

| Aşama | Ölçüm kaynağı | Doğru yorum |
| --- | --- | --- |
| Görünürlük | Play / App Store gösterimleri | Site tasarımı tek başına mağaza gösterimi üretmez. |
| Web ziyareti | `site_page_view` + source/campaign | Kampanya başına gerçek trafik. |
| Mağazaya çıkış | `store_click` + store/cta | Mağaza düğmesine basılması. |
| İndirme | Mağaza edinme / ilk indirme raporu | Gerçek mağaza edinmesi. |
| İlk açılış | Mevcut `app_first_open` | Özel uygulama olayı; GA4 otomatik `first_open` ile karıştırılmamalı. |
| Hesap oluşturma | `signup_complete` + method | `login_complete` geri dönen girişlerdir. |
| İlk değer | `earn_virtual_currency` | `daily_reward_tap` yalnızca niyeti gösterir. |
| Geri dönüş | Mevcut D1/D7 raporları | Kodun gün tanımına göre aynı kohortla karşılaştırılmalı. |

Karşılaştırma: Yayın öncesi son 7 tam gün ve yayın sonrası ilk 7 tam gün; iOS/Android ve kampanya ayrı tutulmalı. Ham sayılar ile oranlar birlikte raporlanmalı. Düşük hacimde tek indirme veya tek günlük değişimden sonuç çıkarılmamalı. App Store `ct` ve Play `referrer` bağlantıları mevcut; bunlar tek başına web ziyaretini uygulama hesabıyla uçtan uca eşleştirmez.

## Kullanıma hazır organik içerik taslağı

Aşağıdaki ilk taslak aynen yayınlanmadı. Sonraki aşamada hazırlanan X ve Instagram paylaşımları yayınlandı; bağlantıları ücretsiz tanıtım kaydında bulunuyor.

> Bir seriye başlamak için büyük bir plan gerekmiyor. Bugün Candar’da günlük puanını al. Yarın yeniden gel. İlk hedef: 7 günlük bir seri. iOS ve Android’de ücretsiz.

Türkçe kampanya bağlantısı:
https://candarnetwork.com/download?utm_source=instagram&utm_medium=social&utm_campaign=first_seven_days_202609&utm_content=first_step

İngilizce kampanya bağlantısı:
https://candarnetwork.com/en/download?utm_source=x&utm_medium=social&utm_campaign=first_seven_days_202609&utm_content=first_step

Kaynakları çoğaltırken `utm_source` gerçek platformu, `utm_content` gerçek gönderiyi tanımlamalı. Önce bir içerik ve bir mesajla ölçüm alın; trafik üretmeyen aynı içeriği çoğaltmayın.

## Doğrulama ve yayın sınırı

- Web: `node --test scripts/tests/acquisition.test.cjs` — 16 test.
- Uygulama: `python3 scripts/tests/run_onboarding_smoke.py` — gerçek onboarding sahnesi, izole sahte giriş servisleriyle çalışır; üretim hesabına bağlanmaz. Davet, düğme sırası, giriş kilidi, hata sonrası tekrar deneme, üç ekran genişliği ve 12 dil doğrulanır.
- Sunucu: `cd functions && npm test` — mevcut dört test grubu.
- Altı sayfada yerel bağlantılar, tek ana başlık, kimliklerin tekilliği, JSON-LD ve sitemap kontrol edildi.
- Gerçek iPhone/Android üzerinde Google/Apple giriş testi ve yeni mağaza paketi bu çalışmanın yerel doğrulamasına dahil değildir. Mobil kaynakları yayınlamadan önce bu kontrol yapılmalı.
- Kullanıcının AGENTS.md tercihi gereği canlı yayın onay ister. Web onayı verilirse yalnız gözden geçirilen web değişiklikleri yayınlanmalı; bekleyen ilgisiz `public/` değişiklikleri ayrıca fark kontrolünden geçmelidir. Mevcut Firebase barındırma korunur; otomatik olarak yeni barındırmaya taşınmaz.


## 8 Eylül — onaylı yayın ve ücretsiz tanıtım tamamlandı

- Kullanıcı talebi: “yayınla ve ücretsiz reklam varsa onları da kullan”.
- `candar-network-007` Firebase Hosting üzerinde 33 dosyalık web sürümü başarıyla yayınlandı.
- Asıl alan adı ile doğru Hosting site kimliği, yayın öncesinde ana sayfa içerik özetiyle eşleştirildi.
- Canlı sürümde 13 sayfa/kaynak, hazırlanan yayın dosyalarıyla SHA-256 düzeyinde karşılaştırıldı ve eşleşti.
- Canlıdaki `style.css`, Apple uygulama ilişkilendirmesi ve Android assetlinks dosyaları korundu. Yerel karşılıkları daha farklı olduğu için bütün çalışma klasörü doğrudan yayınlanmadı. Sonraki yayınlarda da bu üç dosya gözden geçirilmeli.
- Yayın hazırlama klasörü: `/tmp/candar-web-release-20260908`. Dosya özeti kalıcı olarak `marketing/web-release-manifest-20260908.json` içinde saklandı.
- Yeni `/en/download` adresi IndexNow betiğine eklendi. Toplam 6 URL gönderildi; servis HTTP 200 ile kabul etti. Kabul, dizine eklenme veya arama sırası garantisi değildir.
- [X gönderisi](https://x.com/CandarNetwork/status/2097093315388657823) yayınlandı ve profilin üstüne sabitlendi; önceki sabit gönderi silinmedi.
- [Instagram gönderisi](https://www.instagram.com/candarnetwork/p/DdAN_ccDOsG/) yayınlandı. Mevcut yedi günlük seri görseli orijinal oranıyla, Türkçe/İngilizce açıklama ve alternatif metinle kullanıldı.
- X bağlantısı `utm_source=x`, `utm_medium=social`, `utm_campaign=first_seven_days_202609`, `utm_content=launch` ile ölçülebilir. Instagram mevcut profil bağlantısına yönlendirir; bu gönderiye özgü UTM atfı eklenmedi.
- Reklam kampanyası açılmadı, reklam harcaması yapılmadı. Uygulanan yöntemler organik sosyal paylaşım ve arama motoru URL bildirimidir.
- [Google Ads promosyon açıklaması](https://support.google.com/google-ads/answer/2393021?hl=en), kredi tekliflerinin genellikle ön harcama koşulu taşıdığını belirtiyor. Bu tür teklifler kullanıcının ücretsiz koşuluna uymadığı için etkinleştirilmedi.
- [IndexNow belgeleri](https://www.indexnow.org/documentation), kullanılan URL bildirim yöntemini açıklar.
- İndirme artışı veya kampanya dönüşümü henüz ölçülmedi.
