const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const publicDir = path.resolve(__dirname, '../../public');
const source = name => fs.readFileSync(path.join(publicDir, name), 'utf8');
function element(attrs = {}) {
  return { attrs, hidden: true, textContent: '', classList: { values: [], add(s) { this.values.push(s); } }, listeners: {},
    get href() { return this.attrs.href; }, set href(v) { this.attrs.href = v; },
    getAttribute(k) { return this.attrs[k] || null; }, hasAttribute(k) { return k in this.attrs; },
    addEventListener(k, fn) { this.listeners[k] = fn; }, insertAdjacentElement() {} };
}
function page(url = 'https://candarnetwork.com/', options = {}) {
  const links = options.links || [];
  const items = options.items || {};
  const storage = options.storage || new Map();
  const context = vm.createContext({ URL, URLSearchParams, Date, console,
    window: {location: new URL(url)},
    navigator: options.navigator || {userAgent: 'Desktop'},
    sessionStorage: {getItem(k) { if (options.blockStorage) throw Error('blocked'); return storage.get(k); }, setItem(k,v) { if (options.blockStorage) throw Error('blocked'); storage.set(k,v); }},
    document: {documentElement: {lang: options.lang || 'tr'}, body: element({'data-page-type': options.type || 'homepage','data-recommended-label':'Recommended'}),
      querySelectorAll() { return links; }, querySelector() { return element(); }, getElementById(id) { return items[id] || null; }, createElement() { return element(); }}
  });
  vm.runInContext(source('acquisition.js'), context);
  return {context, storage, api: context.window.CandarAcquisition, run(name) { vm.runInContext(source(name), context); }};
}
test('true direct visit is not mislabeled social', () => {
  const {api} = page(); assert.equal(api.context.utm_source, 'direct'); assert.equal(api.context.utm_medium, 'none');
});
test('UTM source takes precedence over legacy placement src', () => {
  const {api} = page('https://candarnetwork.com/?src=site_hero&utm_source=instagram&utm_medium=social&utm_campaign=seven_days');
  assert.equal(api.context.utm_source, 'instagram');
  const target = api.withContext('/download?src=site_footer&utm_campaign=download', 'hero');
  assert.equal(target.searchParams.get('utm_campaign'), 'seven_days'); assert.equal(target.searchParams.has('src'), false);
});
test('campaign survives guide, language switch and download', () => {
  const first = page('https://candarnetwork.com/?utm_source=x&utm_medium=social&utm_campaign=week1&utm_content=post2&ref=friend7');
  const guide = page('https://candarnetwork.com/guides/7-day-streak-challenge', {storage: first.storage});
  const next = guide.api.withContext('/en/download', 'language');
  const download = page(next.href, {storage: first.storage});
  const store = new URL(download.api.storeURL('android', 'download_android'));
  const ref = new URLSearchParams(store.searchParams.get('referrer'));
  assert.equal(ref.get('utm_source'), 'x'); assert.equal(ref.get('utm_content'), 'post2'); assert.equal(ref.get('ref'), 'FRIEND7');
});
test('new campaign clears stale attribution and referral', () => {
  const first = page('https://candarnetwork.com/?utm_source=x&utm_content=old&ref=OLD123');
  const second = page('https://candarnetwork.com/?utm_source=instagram', {storage: first.storage});
  assert.equal(second.api.context.ref, ''); assert.equal(second.api.context.utm_content, '');
});
test('session expires after 30 minutes', () => {
  const storage = new Map([['candar_acquisition_v1', JSON.stringify({at: Date.now()-1800001, utm_source:'old',ref:'OLD123'})]]);
  assert.equal(page(undefined, {storage}).api.context.utm_source, 'direct');
});
test('storage failure does not break links', () => {
  const {api} = page('https://candarnetwork.com/?utm_source=x&ref=abc123', {blockStorage: true});
  assert.equal(api.withContext('/download').searchParams.get('ref'), 'ABC123');
});
test('malformed storage is ignored', () => {
  assert.equal(page(undefined, {storage:new Map([['candar_acquisition_v1','{invalid']])}).api.context.utm_source, 'direct');
});
test('invalid referral is rejected instead of silently altered', () => {
  for (const code of ['ab','friend<script>','a'.repeat(33)]) assert.equal(page('https://candarnetwork.com/?ref='+encodeURIComponent(code)).api.context.ref, '');
});
test('iPad desktop mode chooses App Store', () => {
  assert.equal(page(undefined, {navigator:{userAgent:'Macintosh', platform:'MacIntel',maxTouchPoints:5}}).api.platform,'ios');
});
test('App Store campaign token is bounded and store IDs are fixed', () => {
  const {api} = page('https://candarnetwork.com/?utm_source='+'x'.repeat(100));
  const ios = new URL(api.storeURL('ios')); assert.ok(ios.searchParams.get('ct').length<=40); assert.equal(ios.pathname,'/app/id6756212781');
  assert.equal(new URL(api.storeURL('android')).searchParams.get('id'),'com.candarnetwork.app');
});
test('direct store click emits exactly one store_click, without query or invite code', () => {
  const link = element({href:'https://apps.apple.com/app/id6756212781','data-store':'ios','data-track':'hero_ios'});
  const p = page('https://candarnetwork.com/?utm_source=x', {links:[link]});p.run('site.js');link.listeners.click();
  assert.equal(p.context.window.dataLayer.filter(e=>e.event==='store_click').length,1);
  assert.equal(p.context.window.dataLayer.find(e=>e.event==='site_cta_click').destination,'https://apps.apple.com/app/id6756212781');
});
test('referred homepage uses copy step and does not count an internal click as store conversion', () => {
  const link=element({href:'https://apps.apple.com/app/id6756212781','data-store':'ios','data-track':'hero_ios'});
  const p=page('https://candarnetwork.com/en/?ref=FRIEND7', {links:[link],lang:'en'});p.run('site.js');link.listeners.click();
  assert.equal(new URL(link.href).pathname,'/en/download');
  assert.equal(p.context.window.dataLayer.filter(e=>e.event==='store_click').length,0);
  assert.ok(!JSON.stringify(p.context.window.dataLayer).includes('FRIEND7'));
});
test('download page records one view and one store click without automatic clipboard writes', () => {
  let writes=0;
  const link=element({href:'https://play.google.com/store/apps/details?id=com.candarnetwork.app','data-store':'android','data-track':'download_android'});
  const p=page('https://candarnetwork.com/download?ref=FRIEND7', {links:[link],type:'download',navigator:{userAgent:'Android',clipboard:{writeText(){writes++;return Promise.resolve();}}}});
  p.run('site.js');p.run('download.js');link.listeners.click();
  assert.equal(writes,0);assert.equal(p.context.window.dataLayer.filter(e=>e.event==='download_page_view').length,1);
  assert.equal(p.context.window.dataLayer.filter(e=>e.event==='store_click').length,1);
});
test('explicit copy preserves the app clipboard format and announces success', async () => {
  let copied='';
  const items={inviteCodeCard:element(),inviteCodeValue:element(),copyInviteCode:element({'data-success':'Kopyalandı','data-failure':'Hata'}),copyInviteStatus:element()};
  const p=page('https://candarnetwork.com/download?ref=abc123',{type:'download',items,navigator:{clipboard:{writeText(value){copied=value;return Promise.resolve();}}}});
  p.run('download.js');items.copyInviteCode.listeners.click();await new Promise(setImmediate);
  assert.equal(copied,'candar_ref=ABC123');assert.equal(items.copyInviteStatus.textContent,'Kopyalandı');assert.equal(items.inviteCodeCard.hidden,false);
});
test('clipboard rejection has a visible manual fallback', async () => {
  const items={copyInviteCode:element({'data-failure':'Elle kopyala'}),copyInviteStatus:element()};
  const p=page('https://candarnetwork.com/download?ref=abc123',{type:'download',items,navigator:{clipboard:{writeText(){return Promise.reject(Error('denied'));}}}});
  p.run('download.js');items.copyInviteCode.listeners.click();await new Promise(setImmediate);
  assert.equal(items.copyInviteStatus.textContent,'Elle kopyala');
});
test('every site.js page loads acquisition first and store anchors work without JavaScript', () => {
  for(const file of ['index.html','en/index.html','download.html','en/download.html','guides/7-day-streak-challenge.html','guides/daily-streak-app.html']){
    const html=source(file);assert.ok(html.indexOf('/acquisition.js')<html.indexOf('/site.js'),file);
    if(file.includes('guides/'))continue;
    assert.ok(html.includes('href="https://apps.apple.com/app/id6756212781"'),file);
    assert.ok(html.includes('href="https://play.google.com/store/apps/details?id=com.candarnetwork.app"'),file);
  }
});
