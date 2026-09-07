import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
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
else if (await id('home.start').isExisting()) { await id('home.start').click(); await sleep(4400); }
if (await id('rest.screen').isExisting()) { await id('rest.continue').click(); await sleep(600); }
await id('slide.finish').waitForExist({ timeout: 10000 });
await slide(); await sleep(1100);
if (await id('slide.finish').isExisting()) await slide();
await driver.saveScreenshot(`${SC}/racked-instant.png`);   // first frame after the slide
await sleep(600);
await driver.saveScreenshot(`${SC}/racked.png`);         // mid-splash
await id('summary.done').waitForExist({ timeout: 20000 });
console.log('summary reached');
await driver.deleteSession();
