import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const count = async () => {
  const e = await driver.$('-ios predicate string:label CONTAINS "HISTORY"');
  return (await e.isExisting()) ? await e.getAttribute('label') : 'n/a';
};
await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
await sleep(800);
await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: ['--today', '2026-09-06', '--coach-fixture'] });
await sleep(3000);
await driver.$('~nav.tab.calendar').click(); await sleep(1200);
for (let i = 0; i < 4; i++) { await driver.execute('mobile: swipe', { direction: 'up' }); await sleep(320); }
const all = await driver.$('-ios predicate string:label == "ALL"');
if (await all.isExisting()) { await all.click(); await sleep(900); }
for (let i = 0; i < 2; i++) { await driver.execute('mobile: swipe', { direction: 'up' }); await sleep(320); }
console.log('before:', await count());
const win = await driver.getWindowSize();
const rows = await driver.$$('~history.row');
let r = null, l = null, s = null;
for (const row of rows) {
  const loc = await row.getLocation(), sz = await row.getSize();
  if (loc.y > 130 && loc.y + sz.height < win.height - 130) { r = row; l = loc; s = sz; break; }
}
if (!r) { console.log(`no visible row among ${rows.length}`); await driver.deleteSession(); process.exit(0); }
// swipe that row open
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width * 0.7), y: Math.round(l.y + s.height / 2) },
  { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 },
  { type: 'pointerMove', duration: 380, x: Math.round(l.x + s.width * 0.7 - 130), y: Math.round(l.y + s.height / 2) },
  { type: 'pause', duration: 200 }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(800);
await driver.saveScreenshot(`${SC}/history-swipe.png`);
// probe where the pill actually is: tap candidates until the count drops
const y = Math.round(l.y + s.height / 2);
for (const dx of [48, 90, 130]) {
  const x = Math.round(l.x + s.width - dx);
  const было = await count();
  await driver.performActions([{ type: 'pointer', id: 'f2', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 70 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions(); await sleep(2200);
  const now = await count();
  console.log(`tap at rowRight-${dx} (x=${x}): ${было} -> ${now}`);
  if (now !== было) break;
}
console.log('after: ', await count());
await driver.saveScreenshot(`${SC}/history-after.png`);
await driver.deleteSession();
