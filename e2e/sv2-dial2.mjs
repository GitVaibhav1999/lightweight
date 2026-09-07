import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
if (await id('resume.bar').isExisting()) await id('resume.bar').click();
await id('slide.finish').waitForExist({ timeout: 8000 }); await sleep(600);
const chip = await id('rest.chip'); const cl = await chip.getLocation(), cs = await chip.getSize();
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: Math.round(cl.x + cs.width/2), y: Math.round(cl.y + cs.height/2) },
  { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 700 }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(900);
const dial = await id('rest.dial');
console.log('dial exists:', await dial.isExisting());
const dl = await dial.getLocation(), ds = await dial.getSize();
console.log('dial rect:', dl, ds);
const cx = dl.x + ds.width/2, cy = dl.y + ds.height/2;
// drag along the ring from 90deg (3 o'clock, r=88) to 180deg (6 o'clock) in element-true coords
const p = (deg, r=88) => ({ x: Math.round(cx + r*Math.sin(deg*Math.PI/180)), y: Math.round(cy - r*Math.cos(deg*Math.PI/180)) });
const a1 = p(60), a2 = p(120), a3 = p(150);
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: a1.x, y: a1.y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 150 },
  { type: 'pointerMove', duration: 400, x: a2.x, y: a2.y }, { type: 'pointerMove', duration: 300, x: a3.x, y: a3.y },
  { type: 'pause', duration: 200 }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(700);
await driver.saveScreenshot('/tmp/sv2-g-dial-drag.png');
console.log('chip after drag:', await id('rest.chip').getAttribute('label').catch(() => '?'));
await driver.deleteSession();
