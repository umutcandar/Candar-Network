# Candar Network — 12-language release package

## Scope

12 supported languages in this exact order:

| Code | Language |
| --- | --- |
| en | English |
| tr | Türkçe |
| de | Deutsch |
| fr | Français |
| es | Español |
| pt | Português |
| ru | Русский |
| zh | 简体中文 |
| ja | 日本語 |
| ko | 한국어 |
| ar | العربية |
| hi | हिन्दी |

All **313 pre-existing CSV keys** remain present with 12 nonempty translations.
The 4 main dynamically built screens (Home, Market, Profile, Chat),
plus newly added team dialogs and the onboarding exceptions, use the separate
`localization/ui_strings.json` catalog: currently **169 runtime UI strings**
in 12 locales and **18 named string families** covering streak/badge labels
and localized Firebase error categories.

### Runtime architecture

1. `Global._determine_initial_lang()` first reads the explicit
   `user://settings.cfg` preference, then falls back to the device locale
   and finally `en`.
2. `Global.set_language(code)` saves the preference, updates
   `TranslationServer`, and synchronizes push language when signed in.
3. The `LocalizedLabel`, `LocalizedButton`, and `LocalizedLineEdit`
   scene scripts keep using Godot's built-in `tr("key")` against the existing
   `candar_translations.*.translation` resources.
4. Dynamically created screens call `Global.localized_ui_text(tr, en)`,
   which looks up `en` in the runtime JSON catalog and applies the current
   2-letter locale. No external translation API or network is needed.
5. The extra `Global.localized_named_key(key)` handles previously missing
   badges, streak notifications, and Firebase callable errors. Unknown keys
   fall back to the Godot translation system.
6. Both onboarding (before sign-in) and the profile contain a language
   selector. Selecting a language reloads the current scene and reapplies
   existing `tr()` placeholders plus dynamic UI messages. Existing login
   tokens are not rewritten.
7. Both Android and iOS `export_presets.cfg` explicitly include
   `localization/ui_strings.json` in the packaged game.

### Adding a new dynamic UI label

- Call `_ui_text("Turkish text", "English text")` in Home, Market, Profile
  or Chat. For onboarding exceptions use `Global.localized_ui_text`.
- Add the exact English text to `localization/ui_strings.json.keys` and one
  corresponding value at the **same index** in every locale array.
- Keep `%s`, `%d`, `%.2f`, and `\n` formatting and newline structure
  identical, including the number and order of printf placeholders.
- Run `node --test scripts/tests/i18n_catalog.test.cjs`.
  It fails if any `_ui_text` literal is missing, any language value is blank,
  any placeholder is mismatched, any `tr("key")` reference is missing from
  the original CSV, or the JSON is missing from either mobile export.
- Run `python3 scripts/tests/run_localization_smoke.py` with Godot 4.6.
  It executes the **actual GDScript runtime methods**, tests each locale,
  tries the two language selectors, checks persistence and localized
  Firebase error categories.

### QA and known boundaries

Automated coverage guarantees **nonempty strings and placeholder structure**,
not professional linguistic quality. Before international store launch:

- Native-speaker review and proofreading for German, French, Spanish,
  Portuguese, Russian, Chinese, Japanese, Korean, Arabic and Hindi;
  `pt` currently uses broadly Brazilian-friendly wording.
- Test actual iOS and Android builds for glyph coverage and line wrapping:
  Arabic right-to-left/bidi, Devanagari shaping, Chinese/Japanese/Korean
  fonts, mixed LTR numerals and codes, long German labels and button fit.
- Check that the chosen language persists after app termination and account
  relogin, and that error messages from payment, AI, team, network and
  account deletion screens use the expected language.
- Check server-generated emails and push notification content independently;
  client localization does **not** automatically translate Firebase Auth
  system emails or Google/Apple store purchase dialogs.
- Confirm `res://localization/ui_strings.json` exists in the final IPA/AAB
  and that the Xcode/Gradle native builds pass on real devices.

This implementation is on draft PR #1 and is **not currently live**.
