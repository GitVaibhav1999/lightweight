import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
const shot = (n) => driver.saveScreenshot(`/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad/${n}.png`);
await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
await sleep(800);
await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: ['--today', '2026-09-05', '--coach-fixture'] });
await sleep(2400);
// clear the live session so home shows its resting state
if (await id('live.pill').isExisting()) {
  await id('live.pill').click(); await sleep(1200);
  const f = id('slide.finish'); const l = await f.getLocation(), s = await f.getSize(); const y = Math.round(l.y + s.height / 2);
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width * 0.08), y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 },
    { type: 'pointerMove', duration: 900, x: Math.round(l.x + s.width * 0.99), y }, { type: 'pause', duration: 150 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions(); await sleep(1200);
  // unchecked sets arm a confirm slide — the finish needs a second pass
  if (await id('slide.finish').isExisting()) {
    const l2 = await id('slide.finish').getLocation(), s2 = await id('slide.finish').getSize(); const y2 = Math.round(l2.y + s2.height / 2);
    await driver.performActions([{ type: 'pointer', id: 'f2', parameters: { pointerType: 'touch' }, actions: [
      { type: 'pointerMove', duration: 0, x: Math.round(l2.x + s2.width * 0.08), y: y2 }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 },
      { type: 'pointerMove', duration: 900, x: Math.round(l2.x + s2.width * 0.99), y: y2 }, { type: 'pause', duration: 150 }, { type: 'pointerUp', button: 0 } ] }]);
    await driver.releaseActions();
  }
  await sleep(2500);
  if (await id('summary.done').isExisting()) { await id('summary.done').click(); await sleep(1500); }
}
await id('nav.fresh').waitForExist({ timeout: 12000 });   // the + only returns once nothing is live
await sleep(600); await shot('home-rest');
await id('nav.fresh').click(); await sleep(1400); await shot('start-sheet-9a');
console.log('shots done');
await driver.deleteSession();
