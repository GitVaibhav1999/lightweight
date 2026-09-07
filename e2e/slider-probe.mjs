import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:processArguments': { args: ['--today', '2026-08-27'] }, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const el = await driver.$('~slide.start'); await el.waitForExist({ timeout: 15000 }); await sleep(600);
const l = await el.getLocation(), s = await el.getSize();
console.log('slider frame:', JSON.stringify({ ...l, ...s }), 'window:', JSON.stringify(await driver.getWindowSize()));
await driver.saveScreenshot('./shots/sl-rest.png');
// hold mid-drag at ~45% and screenshot while the finger is down
const y = Math.round(l.y + s.height / 2), x1 = Math.round(l.x + 28), x2 = Math.round(l.x + s.width * 0.45);
driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: x1, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 100 },
  { type: 'pointerMove', duration: 500, x: x2, y }, { type: 'pause', duration: 2500 }, { type: 'pointerUp', button: 0 } ] }]).then(() => driver.releaseActions());
await sleep(1400); await driver.saveScreenshot('./shots/sl-mid.png');
await sleep(2500);
await driver.deleteSession();
