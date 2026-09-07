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
await driver.saveScreenshot('/tmp/sl-rest.png');                       // at rest: no glow
const el = id('slide.start'); const l = await el.getLocation(), s = await el.getSize();
const y = Math.round(l.y + s.height / 2);
// hold mid-drag to catch the effects state
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width * 0.10), y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 120 },
  { type: 'pointerMove', duration: 500, x: Math.round(l.x + s.width * 0.62), y }, { type: 'pause', duration: 1200 } ] }]);
await driver.saveScreenshot('/tmp/sl-mid.png');                        // mid-drag: no ground strike
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width * 0.62), y }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(900);
await driver.deleteSession();
