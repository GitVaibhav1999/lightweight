import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
const rect = async (s) => { const el = id(s); const l = await el.getLocation(), z = await el.getSize(); return { y: l.y, h: z.height, bottom: l.y + z.height }; };
const drag = async (el, ms = 450) => { const l = await el.getLocation(), s = await el.getSize(); const y = Math.round(l.y + s.height/2);
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width*0.10), y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 100 },
    { type: 'pointerMove', duration: ms, x: Math.round(l.x + s.width*0.97), y }, { type: 'pause', duration: 200 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions(); };
await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
await sleep(900);
await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: ['--today', '2026-08-27', '--coach-fixture'] });
await sleep(2000);
// clear any live session from the previous run
if (await id('live.pill').isExisting()) {
  await id('live.pill').click(); await sleep(900);
  for (let i = 0; i < 3 && !(await id('summary.done').isExisting()); i++) {
    if (await id('slide.finish').isExisting()) { await drag(id('slide.finish')); await sleep(450); }
    if (await id('slide.finish').isExisting()) { await drag(id('slide.finish')); }
    await sleep(1200);
  }
  if (await id('summary.done').isExisting()) { await id('summary.done').click(); await sleep(1400); }
}
await id('slide.start').waitForExist({ timeout: 10000 }); await sleep(700);
const pill = await rect('slide.start'), tab = await rect('nav.tab.home');
console.log('slide pill bottom:', Math.round(pill.bottom), '· nav top:', Math.round(tab.y), '· gap:', Math.round(tab.y - pill.bottom));
await driver.saveScreenshot('/tmp/nav-idle2.png');
await id('nav.tab.calendar').click(); await sleep(900);
await driver.saveScreenshot('/tmp/nav-calendar.png');
await id('nav.tab.workouts').click(); await sleep(900);
await driver.saveScreenshot('/tmp/nav-workouts.png');
await driver.deleteSession();
