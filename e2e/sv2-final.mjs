import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
const shot = (n) => driver.saveScreenshot(`${SC}/${n}.png`);
const slideFinish = async () => {
  const f = id('slide.finish'); const l = await f.getLocation(), s = await f.getSize(); const y = Math.round(l.y + s.height / 2);
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width * 0.08), y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 },
    { type: 'pointerMove', duration: 900, x: Math.round(l.x + s.width * 0.99), y }, { type: 'pause', duration: 150 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions(); await sleep(1200);
};
await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
await sleep(800);
await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: ['--today', '2026-09-05', '--coach-fixture'] });
await sleep(2400);
if (await id('live.pill').isExisting()) {                       // clear any stale live session
  await id('live.pill').click(); await sleep(1200);
  await slideFinish(); await slideFinish();
  if (await id('summary.done').isExisting()) { await id('summary.done').click(); await sleep(1500); }
}
await id('home.start').waitForExist({ timeout: 10000 }); await sleep(700);
await shot('final-home');
await id('home.start').click(); await sleep(2600);              // splash → session
await id('rest.chip').waitForExist({ timeout: 8000 });
await shot('final-session');
await id('rest.chip').click(); await sleep(900);                // tap idle chip = start + raise rest screen
await shot('final-rest');
await id('rest.screen').click(); await sleep(700);              // any tap drops back
await shot('final-after-rest');
console.log('rest screen up?', await id('rest.screen').isExisting());
await driver.deleteSession();
