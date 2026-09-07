import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
await sleep(900);
await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: ['--today', '2026-08-27', '--coach-fixture'] });
await sleep(2200);
const el = id('slide.start'); const l = await el.getLocation(), s = await el.getSize();
const y = Math.round(l.y + s.height / 2);
// slow drag to ~70% then back — the video captures the expanding fill
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width * 0.10), y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 200 },
  { type: 'pointerMove', duration: 1600, x: Math.round(l.x + s.width * 0.70), y }, { type: 'pause', duration: 900 },
  { type: 'pointerMove', duration: 900, x: Math.round(l.x + s.width * 0.12), y }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(800);
await driver.deleteSession();
