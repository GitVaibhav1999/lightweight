import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
await sleep(900);
await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: ['--today', '2026-08-27', '--coach-fixture'] });
await sleep(2400);
const el = id('start.handle'); await el.waitForExist({ timeout: 8000 });
const l = await el.getLocation(), s = await el.getSize(); const win = await driver.getWindowSize();
const x = Math.round(l.x + s.width / 2), y0 = Math.round(l.y + s.height / 2);
const at = (f) => Math.round(y0 - win.height * f);
// slow pull to 35%, hold, on to 75%, hold, release -> launches
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x, y: y0 }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 200 },
  { type: 'pointerMove', duration: 900, x, y: at(0.35) }, { type: 'pause', duration: 900 },
  { type: 'pointerMove', duration: 700, x, y: at(0.75) }, { type: 'pause', duration: 900 },
  { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions();
await id('slide.finish').waitForExist({ timeout: 10000 });
console.log('landed in session');
await driver.deleteSession();
