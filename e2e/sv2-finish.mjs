import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
const slide = async () => {
  const f = id('slide.finish'); const l = await f.getLocation(), s = await f.getSize(); const y = Math.round(l.y + s.height / 2);
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width * 0.08), y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 },
    { type: 'pointerMove', duration: 800, x: Math.round(l.x + s.width * 0.99), y }, { type: 'pause', duration: 150 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions();
};
await sleep(500);
if (await id('home.resume').isExisting()) { await id('home.resume').click(); await sleep(1400); }
else if (await id('home.start').isExisting()) { await id('home.start').click(); await sleep(4200); }
await id('slide.finish').waitForExist({ timeout: 10000 });
await slide(); await sleep(1200);                       // arms the confirm
const t = Date.now();
if (await id('slide.finish').isExisting()) await slide();
await id('summary.done').waitForExist({ timeout: 20000 });
console.log(`session → summary in ${Date.now() - t}ms`);
await driver.deleteSession();
