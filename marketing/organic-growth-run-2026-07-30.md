# Candar Organik Büyüme Operasyonu — 30 Temmuz 2026

## Başlangıç durumu

- Google Play kamuya açık mağaza rozeti: `100+` indirme.
- Firebase/GA4 son 28 gün: 29 aktif kullanıcı.
- Firebase/GA4 son 7 gün: 29 aktif kullanıcı.
- Firebase/GA4 son 1 gün: 4 aktif kullanıcı.
- Firebase Authentication Temmuz tepe DAU: 19.
- Firebase Authentication Temmuz MAU: 40.
- X: 13 gönderi, 3 takipçi; 26 Temmuz 7 günlük seri videosu 5 organik görüntülenme.
- Instagram: 5 gönderi, 2 takipçi; 7 günlük seri Reel’i yayında.
- Son 28 gün olayları: `app_screen_view` 285, `app_engagement_sync` 132,
  `open_profile` 18, `daily_reward_tap` 16, `earn_virtual_currency` 16,
  `login_apple_tap` 13, `open_chat` 12.

## Uygulanan ücretsiz edinme altyapısı

- Ana sayfa başlığı ve açıklaması marka dışı `günlük seri`, `puan` ve `Candar AI`
  aramalarına göre netleştirildi.
- Türkçe ve İngilizce sayfalar `hreflang` ile birbirine bağlandı.
- SoftwareApplication ve FAQ yapılandırılmış verisi eklendi.
- İki özgün organik rehber yayına alındı:
  - `/guides/7-day-streak-challenge`
  - `/guides/daily-streak-app`
- Ana sayfaya rehber bağlantıları ve gerçek FAQ bölümü eklendi.
- Rehber ve CTA tıklamaları için `site_page_view` ile `site_cta_click`
  ölçümü eklendi.
- Sitemap güncellendi ve robots.txt kök sitemap’i göstermeye devam ediyor.
- IndexNow doğrulama anahtarı barındırıldı; 5 URL global IndexNow uç noktasına
  gönderildi. İlk gönderim `HTTP 202 Accepted` aldı.

## Yayınlanan X gönderisi

Bağlantı: https://x.com/CandarNetwork/status/2082586643475693943

```text
Starting a streak is easy. Returning on day 4 is the hard part.

Try this:
1. Pick one tiny action
2. Make progress visible
3. Use a “minimum viable day”
4. Review the system on day 7

Free 7-day guide:
https://candarnetwork.com/guides/7-day-streak-challenge?utm_source=x&utm_medium=social&utm_campaign=organic_guides_20260730&utm_content=day2
```

Görsel: `store-screenshots/play/01-daily-streak.png`

## Yayınlanan Instagram gönderisi

Bağlantı: https://www.instagram.com/candarnetwork/p/DbZJB4CjJYv/

```text
Motivation fades. Visible progress makes the next step obvious.

Day 2 of the Candar Challenge:
✓ Pick one small action
✓ Complete today’s check-in
✓ Use a smaller version on difficult days
✓ Protect the habit, not perfection

Save this for tomorrow. Start your seven days from the link in bio.

#CandarNetwork #DailyStreak #HabitTracker #HabitBuilding #MobileApp
```

Görsel: `store-screenshots/play/01-daily-streak.png`

## Yayınlanan topluluk yanıtları

Yanıtlar bağlantı veya satış cümlesi içermez; yalnızca konuşmaya fayda ekler:

Bağlantı: https://x.com/CandarNetwork/status/2082587009927762339

```text
This is why we prefer a “minimum viable day” over a perfect streak: shrink the
action before the chain breaks, then review what caused the friction. A system
should help you see the cracks early, not punish you afterward.
```

```text
Four days down. The belt may be 73 years away, but the real win is making
tomorrow’s floss impossible to miss—same cue, same place, minimum one tooth on
rough days. Protect the chain 😄
```

Bağlantı: https://x.com/CandarNetwork/status/2082587255240012187

## GA4 ölçüm ayarı

- `signup_complete` anahtar etkinlik olarak işaretlendi.
- `daily_reward_tap` anahtar etkinlik olarak işaretlendi.
- Her iki etkinlik de GA4 `Key events` sekmesinde yıldızlı ve etkin durumda
  doğrulandı.

## Mağaza keşif optimizasyonu

### Google Play

- Başlangıç ölçümü: 63 yüklü kitle, son 28 günde 731 cihaz gösterimi,
  6 edinme ve 2 ilk açılış.
- Varsayılan mağaza sayfası son 28 günde 27 ziyaretçi ve `%14,8` dönüşüm
  gösterdi.
- `Daily streak search intent` adlı, arama anahtar kelimesi hedefli özel mağaza
  sayfası oluşturuldu.
- Türkçe ad `Candar: Günlük Seri & AI`, İngilizce ad
  `Candar: Daily Streaks & AI` olarak ayarlandı.
- Türkçe ve İngilizce kısa/uzun açıklamalar günlük seri, küçük günlük hedef,
  alışkanlık takibi ve Candar AI faydasını ilk satırlarda anlatacak şekilde
  yeniden yazıldı.
- `daily streak`, `habit tracker`, `streak tracker`, `daily habits`,
  `goal tracker`, `daily routine`, `motivation tracker`, `ai assistant`,
  `alışkanlık takip`, `günlük seri`, `günlük hedef` ve benzeri 15 arama
  niyeti eklendi.
- Değişiklikler 30 Temmuz gecesi Google Play incelemesine gönderildi.

### Apple App Store

- `Candar 2.0.17 — Daily Streak Ecosystem` adlı editoryal öne çıkarma adaylığı
  gönderildi.
- Adaylık kimliği:
  `40bc2129-b47a-4cb1-9904-ded0ccb2d26e`.
- `7-Day Candar Challenge` adlı In-App Event oluşturuldu; yeni kullanıcı
  edinme amacı seçildi.
- Etkinlik 31 Temmuz 00:00–7 Ağustos 00:00 (GMT+3) tarihleri için tüm ülke ve
  bölgelerde planlandı.
- Etkinlik kimliği: `6796102847`.
- Etkinlik URL'si:
  `https://apps.apple.com/us/app/id6756212781?eventid=6796102847`.
- Etkinlik, 30 Temmuz gecesi App Store incelemesine gönderildi ve
  `Waiting for Review` durumunda doğrulandı.
- Kullanılan App Store görselleri:
  - `marketing/assets/candar-7-day-event-card-1920x1080.png`
  - `marketing/assets/candar-7-day-event-detail-1080x1920.png`

## Sabah ölçüm otomasyonu

- 31 Temmuz saat 08:30'da Google Play, App Store Connect ve Firebase/GA4
  verilerini başlangıç değerleriyle karşılaştıran tek seferlik kontrol kuruldu.
- Kontrol gerçek edinme, ilk açılış ve kayıt sinyallerini raporlayacak; ödeme,
  sahte hesap ve spam kullanmayacak.

## Sonraki ölçüm

Yayın sonrası 24 ve 72 saatte:

1. X görüntülenme ve profil ziyareti
2. Instagram takipçi olmayan erişimi
3. `site_page_view` kampanya kaynağı
4. `site_cta_click`
5. `store_click`
6. `first_open`
7. `signup_complete`
8. `daily_reward_tap`

Tek içerik en az bir profil ziyareti veya site tıklaması üretmiyorsa aynı format
tekrarlanmayacak; konu veya açılış cümlesi değiştirilecek.
