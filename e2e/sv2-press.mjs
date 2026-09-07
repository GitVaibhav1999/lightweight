import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const e = driver.$('~nav.tab.workouts');
await sleep(600);
const l = await e.getLocation(), s = await e.getSize();
const x = Math.round(l.x + s.width / 2), y = Math.round(l.y + s.height / 2);
// hold the press so the recording catches the pressed state
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 1400 }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(600);
console.log('pressed');
await driver.deleteSession();
