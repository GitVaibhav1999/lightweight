import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
// in-session? long-press minimize -> discard
if (await id('session.minimize').isExisting()) {
  const el = await id('session.minimize'); const l = await el.getLocation(), s = await el.getSize();
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width/2), y: Math.round(l.y + s.height/2) },
    { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 900 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions(); await sleep(800);
  const d = await driver.$('-ios predicate string:label == "Discard session"');
  if (await d.isExisting()) { await d.click(); await sleep(1200); }
}
await id('slide.start').waitForExist({ timeout: 10000 }); await sleep(700);
await driver.saveScreenshot('/tmp/nav-idle.png');
await id('nav.fresh').click(); await sleep(1000);
await driver.saveScreenshot('/tmp/nav-sheet.png');
console.log('start.fresh:', await id('start.fresh').isExisting(), '· saved rows:', (await driver.$$('~start.workout')).length);
// pick a saved workout straight into a session
const rows = await driver.$$('~start.workout');
if (rows.length) { await rows[0].click(); await id('slide.finish').waitForExist({ timeout: 8000 }); await sleep(600); console.log('saved-workout start: OK'); }
await driver.deleteSession();
