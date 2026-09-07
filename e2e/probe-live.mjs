import { remote } from 'webdriverio';
const UDID = '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': UDID, 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const id = s => driver.$(`~${s}`);
await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
await sleep(800);
await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight' });   // NO fixture args → LIVE client
await sleep(2500);
const rect = async el => { const l = await el.getLocation(), s = await el.getSize(); return { x: l.x, y: l.y, w: s.width, h: s.height }; };
const drag = async el => { const r = await rect(el); const y = Math.round(r.y + r.h / 2), x1 = Math.round(r.x + r.w * 0.08), x2 = Math.round(r.x + r.w * 0.99);
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: x1, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 },
    { type: 'pointerMove', duration: 700, x: x2, y }, { type: 'pause', duration: 150 }, { type: 'pointerUp', button: 0 } ] }]); await driver.releaseActions(); };
await id('slide.start').waitForExist({ timeout: 20000 });
await drag(id('slide.start')); await id('slide.finish').waitForExist({ timeout: 10000 }); await sleep(600);
await id('set.check.0').click(); await sleep(300); await id('set.check.1').click(); await sleep(400);
await drag(id('slide.finish')); await id('summary.done').waitForExist({ timeout: 10000 }); await sleep(600);
await driver.execute('mobile: swipe', { direction: 'up' }); await sleep(500);
await id('coach.ask').click(); await id('coach.rpe.1').waitForExist({ timeout: 4000 }); await id('coach.rpe.1').click();
console.log('RPE tapped — waiting up to 90s for live verdict or error…');
for (let i = 0; i < 45; i++) {
  if (await id('coach.verdict').isExisting()) { console.log('LIVE VERDICT RENDERED ✓'); break; }
  if (await id('coach.error').isExisting()) { console.log('ERROR ROW:', await id('coach.error').getAttribute('label')); break; }
  await sleep(2000);
}
await id('summary.done').click().catch(() => {});
await driver.deleteSession();
