# Frame packet: 03-daily-progress

## Project inputs

- Project: /Users/macbook/Documents/CandarNetwork/videos/candar-sponsored-youtube
- Design tokens: /Users/macbook/Documents/CandarNetwork/videos/candar-sponsored-youtube/frame.md
- RULES_DIR: /Users/macbook/.agents/skills/hyperframes-animation/rules

## Assigned storyboard block

## Frame 3 — Daily Progress, Visible

- status: outline
- src: compositions/frames/03-daily-progress.html
- duration: 11.38s
- transition_in: crossfade
- scene: Gerçek Candar ekranları premium cihaz çerçevelerinde seri, puan ve referans akışını gösterir.
- voiceover: "İki bin yirmi yediden önce hesabını oluştur, kalıcı Kurucu Üye rolünü aç. Günlük serini koru, uygulama içi puanlarını topla, referans ağını büyüt."
- poster: 7.0s
- type: feature_showcase
- blueprint: device-surface-showcase (Adapt)
- asset_candidates: assets/candar-daily-streak.png; assets/candar-referral-network.png
- focal: assets/candar-daily-streak.png
- roles: assets/candar-daily-streak.png = cutout; assets/candar-referral-network.png = supporting
- sfx: device-whoosh, click-soft

Vaadi gerçek ürün kanıtına çevirir. Tek bir ekran turu yerine, her dokunuşun görünür ilerlemeye dönüştüğünü gösterir.

Adapt: premium cihaz yüzeyi ve katmanlı ürün kanıtını koru; sanal parmak yerine gerçek ekranların kamera yolculuğunu kullan. İmza hamlesi, bir cihazdan diğerine neden→sonuç yolculuğudur.

Scene 1 (0.0–3.0s): günlük seri ekranı sağdaki büyük cihaz kartı olarak motion-blur streak ile yerleşir; solda “2027'DEN ÖNCE” etiketi ve “Kurucu Üye rolünü aç” başlığı anlatımla birlikte gelir, asymmetric 60/40 ve üç derinlik katmanı kullanılır.
Scene 2 (3.0–5.9s): anlatım “günlük serini koru” derken kamera ilk ekranın seri bölgesine push/focus yapar; turuncu takip kutusu gerçek seri alanını çerçeveler, cihaz dışındaki metin sakin kalır.
Scene 3 (5.9–8.7s): kamera nudge-curve ile ikinci referans ekranına geçer; “PUANLAR” ve “REFERANS AĞI” chip'leri yalnız adları söylendiğinde art arda spring-pop entrance ile açılır.
Scene 4 (8.7–11.2s): iki gerçek ekran split-tilt düzende yan yana dengelenir; merkezde “Her gün görünür ilerleme” cümlesi kısa glow bloom ile gelir ve ürün ekranları bozulmadan hold eder.

## Selected motion rule: nudge-curve

---
name: nudge-curve
description: Slow-fast-slow three-phase group slide — reposition a composed group (word rows, card stacks, lists) to reveal content or make room. No single built-in ease produces it; chain power3.in ramp → linear burst → power4.out tail (10/65/25 distance, tail ≥3× ramp-in in time).
metadata:
  tags: slide, reposition, group-motion, easing, nudge, slow-fast-slow, reveal, layout
---

# Nudge Curve

Slow-fast-slow repositioning of a composed group (word rows, card stacks, lists) to
reveal content or make room. **In-scene group slide — not a seam.** No single built-in
ease produces it — `power4.inOut` smacks to a stop. Chain three tweens on one property:

| Phase     | Ease            | Distance | Time | Feel                                     |
| --------- | --------------- | -------- | ---- | ---------------------------------------- |
| 1 ramp-in | `power3.in`     | ~10%     | ~20% | barely moves — motion registers, no jolt |
| 2 burst   | `none` (linear) | ~65%     | ~18% | ~2× average px/frame — purposeful        |
| 3 tail    | `power4.out`    | ~25%     | ~62% | decaying creep to rest — kills the smack |

## Rules

- The tail is ≥3× the ramp-in in TIME. If it still smacks: extend the tail's time (not
  distance) or use `power5.out`.
- Phase 2 stays linear — easing it loses the burst contrast.
- Reveal new content DURING phase 2 — the burst masks its appearance.
- Same ratios vertical; scale distances proportionally, keep the time ratios.
- A cascade arrival usually precedes this slide — see [waterfall-entry.md](waterfall-entry.md).

## JS

Reference values for a 270px leftward slide (0.57s total). Scale distances
proportionally for other travels; preserve the TIME ratios; tail ≥3× ramp-in.

```js
var t = /* start after content settles */;
tl.to(".text-row", { x: -30,  duration: 0.12, ease: "power3.in"  }, t);          // ramp-in: 11% dist / 21% time
tl.to(".text-row", { x: -210, duration: 0.10, ease: "none"       }, t + 0.12);   // burst:   67% dist / 18% time
tl.to(".text-row", { x: -270, duration: 0.35, ease: "power4.out" }, t + 0.22);   // tail:    22% dist / 61% time
// vertical: same ratios on y. 150px variant: -15 / -115 / -150 at the same times.
```

## Anti-patterns

| Don't                                                    | Instead                                  |
| -------------------------------------------------------- | ---------------------------------------- |
| Single ease for a group slide (`power4.inOut`, `slow()`) | The three-phase chain above              |
| Nudge tail shorter than 3× the ramp-in                   | Extend the tail's TIME, not its distance |
