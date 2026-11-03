# Candar Büyüme Denetimi ve Uygulama Planı — 24 Temmuz 2026

## Yönetici özeti

Ana problem mağaza sayfasına gelen kişinin ikna olmaması değil, mağazada yeterince
gösterim alamamak ve indirme sonrasında ilk açılışa ulaşamamaktır.

- iOS, son 90 gün: 145 gösterim, 65 ürün sayfası görüntülemesi, 8 ilk indirme,
  6 yeniden indirme, ortalama %27,4 dönüşüm.
- Android, son 28 gün: 664 cihaz gösterimi, 8 edinme, 3 ilk açılış ve 29 aylık
  aktif cihaz.
- Android, son 90 gün: Explore kaynaklı yalnızca 30 kullanıcı edinmesi.
- Firebase Authentication: toplam 255 hesap; son görünen yeni kayıt 19 Temmuz.
- Firebase Temmuz kullanımı: en fazla 9 DAU ve 24 MAU.

Bu veriler ücretli trafik artırılmadan önce görünürlük, ilk açılış ve ölçümleme
katmanlarının düzeltilmesi gerektiğini gösteriyor.

## Canlı mağaza ve ürün bulguları

1. App Store Connect'te iOS 2.0.11 `Pending Developer Release` durumunda.
   Onaylanmış ancak manuel olarak yayınlanmamış. Canlı mağazada 2.0.10 var.
2. Google Play'de uygulama Finance kategorisinde. Ürün metni uygulamanın finansal
   hizmet olmadığını söylüyor; kategori yanlış arama kümesine sokuyor.
3. Google Play Data safety, "veri toplanmıyor/paylaşılmıyor" diyor. Uygulama e-posta,
   kullanıcı kimliği, kullanım ve satın alma verisi işlediği için beyan güncellenmeli.
4. Google Play'de Store Listing Experiment sayısı 0. Mevcut %18,52 liste dönüşümü
   deneysiz bırakılmış.
5. Marka adıyla bulunuyor; marka dışı `daily streak`, `referral leaderboard`,
   `AI companion` gibi sorgularda güçlü bir yüzey yok.
6. Web indirme sayfasında `download_page_view` ve `store_click` var; uygulama içi
   Google Analytics ayarları eksik olduğu için `first_open`, kayıt ve günlük ödül
   zinciri güvenilir biçimde ölçülemiyor.

## Kod ve işlev denetiminde yapılanlar

- Açılışı durduran GDScript parse hatası düzeltildi.
- Ana sahne UID yerine güvenli dosya yoluna bağlandı.
- Kayıt profili ve referans bonusu tek sunucu işlemi haline getirildi.
- Referans listesi ve liderlik tablosu Firestore çapraz kullanıcı sorgusu yerine
  yetkili callable işlevlere taşındı.
- Günlük puan, Premium ve boost için istemciden doğrudan Firestore yazan güvensiz
  fallback akışları kapatıldı.
- Kullanıcı puanı, Premium, boost, satın alma ve referans alanlarını istemci
  değişikliklerine kapatan Firestore kuralları hazırlandı.
- Hesap silme; Authentication hesabı ile kullanıcı dokümanı ve alt koleksiyonlarını
  birlikte silecek sunucu akışına taşındı.
- Ham satın alma kanıtı saklamak yerine SHA-256 özeti tutuluyor.
- Mağaza görselleri güvenli giriş ekranıyla değil ürünün günlük seri değer
  önerisiyle başlayacak şekilde yeniden üretildi.

## Yayından önce kapanması gerekenler

### P0 — Büyümeyi durduranlar

1. Hazırlanan Firebase Functions ve Firestore kurallarını yayınla.
2. Yeni Android/iOS pakette gerçek cihaz smoke test uygula:
   e-posta kayıt, Google/Apple giriş, referans kodu, günlük ödül, market,
   Premium/boost satın alma, restore, AI sohbet, bildirim, hesap silme.
3. iOS 2.0.11'i otomatik yayınlama. Kaynak düzeltmelerini içeren yeni build'i
   TestFlight'ta doğrulayıp sonra yayınla.
4. Google Play Data safety formunu gerçek veri akışına göre düzelt.
5. Uygulama içi analitiği yapılandır. En az şu funnel zorunlu:
   `first_open → signup_start → signup_complete → daily_reward → day_1_return`.

### P1 — ASO

Her iki mağaza için önerilen konum:

```text
Name: Candar: Daily Streaks & AI
Subtitle: Points, referrals, leaderboard
Category: Lifestyle
```

App Store keyword alanı (88 karakter):

```text
habit,streak,points,referral,leaderboard,community,social,daily,challenge,progress,boost
```

Google Play kısa açıklama:

```text
Build daily streaks, collect points, invite friends, and explore with Candar AI.
```

Promotional text:

```text
Start a daily streak, collect Candar points, grow your referral network, and use Candar AI to keep moving.
```

Ekran görüntüsü sırası:

1. Build your daily streak
2. Grow your referral network
3. Explore with Candar AI
4. Boost your progress
5. Create your profile

İlk test: mevcut sayfa ile bu değer-önce setini %50/%50 karşılaştır. Ana başarı
metriği install conversion; ikincil metrik first open.

### P2 — Organik edinme

Tek bir büyüme vaadi kullan:

```text
7-Day Candar Streak Challenge
```

- Gün 1: 10–15 saniyelik "seri başlat" videosu.
- Gün 2: puan ve günlük check-in gösterimi.
- Gün 3: arkadaş daveti / referans ağı.
- Gün 4: Candar AI kullanım örneği.
- Gün 5: gerçek kullanıcı ilerleme ekranı.
- Gün 6: "seriyi bozma" hatırlatıcısı.
- Gün 7: sonuç ve yeni katılım çağrısı.

Her içerik tek bir UTM/deep-link kampanya kodu taşımalı. İzlenemeyen içerik
çoğaltılmamalı.

### P3 — Ürün içi büyüme

- İlk başarılı günlük ödülden sonra paylaşılabilir seri kartı.
- 3 başarılı günlük check-in sonrasında, ödülsüz ve baskısız mağaza yorumu istemi.
- Referans linki açıldığında kodu otomatik doldur.
- Yeni kullanıcı için ilk 60 saniyede yalnız üç görev göster:
  profil oluştur, günlük puanı al, yarın geri gel.

## Reklam kararı

Şimdilik geniş ücretli kampanya açma. Aşağıdaki eşikler görülmeden reklam bütçesi
edinmeye değil hata büyütmeye gider:

- acquisition → first open en az %70
- signup completion en az %60
- D1 retention en az %25
- crash-free users en az %99,5

Eşikler sağlandığında yalnız Apple Search Ads exact-match ve Google App Campaign
install optimizasyonuyla küçük test başlat; görüntülenme/etkileşim kampanyası açma.

## Haftalık skor kartı

Her pazartesi şu sekiz metriği tek tabloda karşılaştır:

1. Store impressions
2. Product page views
3. First-time downloads / acquisitions
4. First opens
5. Signup completes
6. Daily reward completes
7. D1 ve D7 retention
8. Crash-free users

İlk 30 günlük hedef: iOS gösterimini 145/90 günden en az 500/30 güne, Android
gösterimini 664/28 günden 2.000/28 güne çıkarmak; bunu ilk açılış ve D1 retention
eşiklerini bozmadan yapmak.

## 25 Temmuz uygulama durumu

- Firebase Functions, güvenli GA4 olay aktarımı ve Firestore rules canlıya alındı.
- iOS 2.0.12 build 49 fiziksel iPhone testlerinden sonra App Store incelemesine
  gönderildi; onaydan sonra otomatik yayın seçildi.
- Mağaza adı `Candar: Daily Streaks & AI`, alt başlığı
  `Rewards, goals & community` olarak güncellendi.
- Yanlış `Finance` kategorisi kaldırıldı; birincil kategori `Lifestyle`,
  ikincil kategori `Productivity` yapıldı.
- Günlük seri kilometre taşları, ilerleme/strateji kartı, tek dokunuşlu Candar AI
  önerileri ve D1/D7 geri dönüş ölçümü ürüne eklendi.
- Ücretli reklam bütçesi açılmadı. Önce yukarıdaki dönüşüm ve tutundurma
  eşiklerinin yeni analitikle doğrulanması gerekiyor.
