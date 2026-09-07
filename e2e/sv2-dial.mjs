import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
await sleep(500);
if (await id('home.resume').isExisting()) { await id('home.resume').click(); await sleep(1400); }
else if (await id('home.start').isExisting()) { await id('home.start').click(); await sleep(4400); }
await id('rest.chip').waitForExist({ timeout: 10000 });
if (await id('rest.screen').isExisting()) { await id('rest.continue').click(); await sleep(600); }
let label = await id('rest.chip').getAttribute('label');
if (/^\d+:\d\d$/.test(label)) { await id('rest.chip').click(); await sleep(700); }   // running → cancel first
console.log('chip before:', await id('rest.chip').getAttribute('label'));
// long-press the chip to open the dial
const c = id('rest.chip'); const l = await c.getLocation(), s = await c.getSize();
const x = Math.round(l.x + s.width / 2), y = Math.round(l.y + s.height / 2);
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 700 }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(800);
const dialUp = await id('rest.dial').isExisting();
await driver.saveScreenshot(`${SC}/dial.png`);
// drag the ring to a new target, then tap the centre to set
if (dialUp) {
  const d = id('rest.dial'); const dl = await d.getLocation(), ds = await d.getSize();
  const cx = Math.round(dl.x + ds.width / 2), cy = Math.round(dl.y + ds.height / 2);
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: cx, y: cy - 100 }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 120 },
    { type: 'pointerMove', duration: 500, x: cx + 95, y: cy + 20 }, { type: 'pause', duration: 200 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions(); await sleep(700);
  console.log('after drag — running?', /^\d+:\d\d$/.test(await id('rest.chip').getAttribute('label')), '| rest screen up?', await id('rest.screen').isExisting());
  await driver.performActions([{ type: 'pointer', id: 'f2', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: cx, y: cy }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 60 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions(); await sleep(800);
}
console.log('after centre tap — chip:', await id('rest.chip').getAttribute('label'), '| dial gone?', !(await id('rest.dial').isExisting()), '| rest screen up?', await id('rest.screen').isExisting());
await driver.deleteSession();
