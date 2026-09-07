import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
const centre = async (n) => { const e = id(n); const l = await e.getLocation(), s = await e.getSize(); return { x: Math.round(l.x + s.width / 2), y: Math.round(l.y + s.height / 2) }; };
await sleep(600);
const a = await centre('nav.tab.home'), c = await centre('nav.tab.calendar');
// press on Home and slide slowly to Calendar, holding at each cell
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: a.x, y: a.y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 500 },
  { type: 'pointerMove', duration: 700, x: Math.round((a.x + c.x) / 2), y: a.y }, { type: 'pause', duration: 800 },
  { type: 'pointerMove', duration: 700, x: c.x, y: a.y }, { type: 'pause', duration: 800 },
  { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(1200);
await driver.saveScreenshot('/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad/nav-after-slide.png');
console.log('landed on calendar page?', await id('header.calendar').isExisting());
await driver.deleteSession();
