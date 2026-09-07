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
    { type: 'pointerMove', duration: 700, x: Math.round(l.x + s.width * 0.99), y }, { type: 'pause', duration: 120 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions();
};
await sleep(500);
// clear any live session so the card offers Start
if (await id('home.resume').isExisting()) {
  await id('home.resume').click(); await sleep(1400);
  if (await id('rest.screen').isExisting()) { await id('rest.continue').click(); await sleep(500); }
  await slide(); await sleep(1000); if (await id('slide.finish').isExisting()) await slide();
  await id('summary.done').waitForExist({ timeout: 25000 }); await id('summary.done').click(); await sleep(1500);
}
await id('home.start').waitForExist({ timeout: 10000 }); await sleep(600);
await id('home.start').click();
await driver.saveScreenshot(`${SC}/start-frame1.png`);   // first frame after the tap
console.log('shot taken');
await driver.deleteSession();
