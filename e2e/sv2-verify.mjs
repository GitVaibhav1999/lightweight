import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
await sleep(1000);
await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: ['--today', '2026-08-27', '--coach-fixture'] });
await sleep(1800);
// enter the session: live -> resume bar, else slide to start
if (await id('resume.bar').isExisting()) { await id('resume.bar').click(); }
else {
  const el = id('slide.start'); await el.waitForExist({ timeout: 8000 });
  const l = await el.getLocation(), s = await el.getSize(); const y = Math.round(l.y + s.height / 2);
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: Math.round(l.x + s.width * 0.08), y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 },
    { type: 'pointerMove', duration: 700, x: Math.round(l.x + s.width * 0.99), y }, { type: 'pause', duration: 150 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions();
}
await id('slide.finish').waitForExist({ timeout: 8000 }); await sleep(800);
// hold chip -> dial
const chip = await id('rest.chip'); const cl = await chip.getLocation(), cs = await chip.getSize();
const cx = Math.round(cl.x + cs.width / 2), cy = Math.round(cl.y + cs.height / 2);
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: cx, y: cy }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 700 }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(900);
console.log('dial open:', await id('rest.dial').isExisting());
await driver.saveScreenshot('/tmp/sv2-d-dial.png');
// drag the pointer along the ring: from ~1:30 angle to ~3:00 side, then it arms on release
const win = await driver.getWindowSize(); const dcx = Math.round(win.width / 2), dcy = Math.round(win.height / 2);
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: dcx + 62, y: dcy - 62 }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 120 },
  { type: 'pointerMove', duration: 600, x: dcx + 88, y: dcy }, { type: 'pause', duration: 150 }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(600);
await driver.saveScreenshot('/tmp/sv2-e-dial-armed.png');
console.log('chip after drag:', await id('rest.chip').getAttribute('label').catch(() => '?'));
// center tap closes
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: dcx, y: dcy }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 60 }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(600);
console.log('dial closed:', !(await id('rest.dial').isExisting()));
await driver.saveScreenshot('/tmp/sv2-f-closed.png');
await driver.deleteSession();
