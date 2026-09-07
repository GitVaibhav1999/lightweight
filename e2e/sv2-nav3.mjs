import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
const drag = async (el, ms = 900) => { const l = await el.getLocation(), s = await el.getSize(); const y = Math.round(l.y + s.height/2);
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width*0.10), y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 120 },
    { type: 'pointerMove', duration: ms, x: Math.round(l.x + s.width*0.97), y }, { type: 'pause', duration: 250 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions(); };
if (await id('live.pill').isExisting()) { await id('live.pill').click(); await sleep(1000); }
for (let i = 0; i < 3 && !(await id('summary.done').isExisting()); i++) {
  if (await id('slide.finish').isExisting()) { await drag(id('slide.finish'), 450); await sleep(450); }   // arm
  if (await id('slide.finish').isExisting()) { await drag(id('slide.finish'), 450); }                     // confirm inside the 3s window
  await sleep(1200);
}
if (await id('summary.done').isExisting()) { await id('summary.done').click(); await sleep(1400); console.log('session finished'); }
await id('slide.start').waitForExist({ timeout: 10000 }); await sleep(700);
await driver.saveScreenshot('/tmp/nav-idle.png');
await id('nav.fresh').click(); await sleep(1000);
await driver.saveScreenshot('/tmp/nav-sheet.png');
console.log('start.fresh:', await id('start.fresh').isExisting(), '· saved rows:', (await driver.$$('~start.workout')).length);
const rows = await driver.$$('~start.workout');
if (rows.length) { await rows[0].click(); await id('slide.finish').waitForExist({ timeout: 8000 }); await sleep(500); console.log('saved-workout start: OK'); }
await driver.deleteSession();
