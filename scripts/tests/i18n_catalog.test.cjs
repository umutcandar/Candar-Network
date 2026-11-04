"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const root = path.resolve(__dirname, "../..");
const langs = ["en", "tr", "de", "fr", "es", "pt", "ru", "zh", "ja", "ko", "ar", "hi"];
const dynamic = JSON.parse(fs.readFileSync(path.join(root, "localization/ui_strings.json"), "utf8"));

function readCsv(text) {
  const result = []; let row = [], field = "", quoted = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') { field += '"'; i++; }
      else quoted = !quoted;
    } else if (c === "," && !quoted) {
      row.push(field); field = "";
    } else if ((c === "\n" || c === "\r") && !quoted) {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(field);
      if (row.some(Boolean)) result.push(row);
      row = []; field = "";
    } else field += c;
  }
  if (field || row.length) { row.push(field); result.push(row); }
  assert.equal(quoted, false, "CSV ends inside quotes");
  return result;
}

function printfSpecs(value) {
  return [...value.matchAll(/%(?:%|(?:0?\d+)?(?:\.\d+)?[sdf])/g)].map(m => m[0]);
}

const csv = readCsv(fs.readFileSync(path.join(root, "candar_translations.csv"), "utf8"));
const csvKeys = new Set(csv.slice(1).map(r => r[0]));
const dynamicKeys = new Set(dynamic.keys);

test("Original CSV has complete, unique translations for all 12 locales", () => {
  assert.deepEqual(csv[0], ["key", ...langs]);
  assert.equal(csvKeys.size, csv.length - 1, "Duplicate base translation key");
  assert.ok(csvKeys.size >= 300);
  for (const row of csv.slice(1)) {
    assert.equal(row.length, 13, "CSV row " + row[0]);
    for (const [i, lang] of langs.entries()) {
      assert.ok(String(row[i + 1] || "").trim(), "Empty CSV " + row[0] + ":" + lang);
    }
  }
});

test("Dynamic UI translations cover every locale and preserve formatting", () => {
  assert.ok(dynamic.keys.length >= 165, "Missing newer dynamic UI messages");
  assert.equal(dynamicKeys.size, dynamic.keys.length, "Duplicate dynamic English key");
  for (const lang of langs) {
    assert.ok(Array.isArray(dynamic[lang]), lang + " dictionary missing");
    assert.equal(dynamic[lang].length, dynamic.keys.length, lang + " key count");
    for (let i = 0; i < dynamic.keys.length; i++) {
      assert.ok(String(dynamic[lang][i]).trim(), lang + " missing " + i);
      assert.deepEqual(printfSpecs(dynamic[lang][i]), printfSpecs(dynamic.keys[i]),
        lang + " placeholders: " + dynamic.keys[i]);
      assert.equal((dynamic[lang][i].match(/\n/g) || []).length,
        (dynamic.keys[i].match(/\n/g) || []).length,
        lang + " newline count: " + dynamic.keys[i]);
    }
  }
  assert.deepEqual(dynamic.en, dynamic.keys);
});

test("Every runtime _ui_text literal is present in 12-language catalog", () => {
  for (const name of ["home.gd", "profile.gd", "market.gd", "chat.gd"]) {
    const source = fs.readFileSync(path.join(root, name), "utf8");
    assert.match(source, /return Global\.localized_ui_text\(tr_text, en_text\)/);
    const pairs = [...source.matchAll(/_ui_text\(\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)/g)];
    assert.ok(pairs.length, name + " must have localized UI messages");
    for (const p of pairs) {
      const en = p[2].replaceAll("\\n", "\n");
      assert.ok(dynamicKeys.has(en), name + ": missing " + en);
    }
  }
});

test("No remaining untranslated tr() keys in app screen sources", () => {
  const screenPaths = [
    "global.gd", "onboarding.gd", "home.gd", "profile.gd", "market.gd", "chat.gd"
  ];
  for (const file of screenPaths) {
    const content = fs.readFileSync(path.join(root, file), "utf8");
    for (const match of content.matchAll(/\btr\(\s*"([^"]+)"\s*\)/g)) {
      assert.ok(csvKeys.has(match[1]), "Missing CSV key " + file + ":" + match[1]);
    }
  }
  for (const name of [
    "badge_starter", "badge_pro", "badge_master", "badge_veteran", "badge_legend",
    "streak_7_bonus", "streak_30_bonus", "streak_100_bonus", "streak_reset",
  ]) {
    assert.ok(dynamic.named[name], name);
    for (const lang of langs) assert.ok(dynamic.named[name][lang], name + ":" + lang);
  }
});

test("Android and iOS exports bundle the runtime locale catalog", () => {
  const presets = fs.readFileSync(path.join(root, "export_presets.cfg"), "utf8");
  const includeRules = [...presets.matchAll(/^include_filter="([^"]*)"/gm)].map(x => x[1]);
  assert.equal(includeRules.length, 2);
  for (const rule of includeRules) {
    assert.ok(rule.split(",").includes("localization/ui_strings.json"), "UI catalog missing from mobile export");
  }
});

test("Login and profile screens expose a real language selector", () => {
  const onboarding = fs.readFileSync(path.join(root, "onboarding.gd"), "utf8");
  const profile = fs.readFileSync(path.join(root, "profile.gd"), "utf8");
  const global = fs.readFileSync(path.join(root, "global.gd"), "utf8");
  assert.match(onboarding, /_build_language_selector\(\)/);
  assert.match(onboarding, /Global\.set_language\(next_locale\)/);
  assert.match(profile, /btn_language\.pressed\.connect\(_show_language_dialog\)/);
  assert.match(profile, /Global\.set_language\(next_language\)/);
  assert.match(global, /saved\.get_value\("general", "lang"/);
  assert.match(global, /func localized_ui_text\(/);
});
