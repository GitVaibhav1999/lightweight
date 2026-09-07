import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
await sleep(500);
if (await id('home.resume').isExisting()) {
  await id('home.resume').click(); await sleep(1200);
  for (let i = 0; i < 2; i++) {
    const f = id('slide.finish'); if (!(await f.isExisting())) break;
    const l = await f.getLocation(), s = await f.getSize(); const y = Math.round(l.y + s.height / 2);
    await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
      { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width * 0.08), y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 },
      { type: 'pointerMove', duration: 800, x: Math.round(l.x + s.width * 0.99), y }, { type: 'pause', duration: 150 }, { type: 'pointerUp', button: 0 } ] }]);
    await driver.releaseActions(); await sleep(1500);
  }
  try { if (await id('summary.done').isExisting()) { await id('summary.done').click(); await sleep(1500); } } catch {}
}
await id('home.start').waitForExist({ timeout: 10000 }); await sleep(500);
await id('home.start').click();
await driver.saveScreenshot(`${SC}/splash-a.png`);      // ~0.6s in
await driver.saveScreenshot(`${SC}/splash-b.png`);      // ~1.4s in
console.log('shots taken');
await driver.deleteSession();
