import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': process.env.SIM_UDID || '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80',
  'appium:bundleId': 'com.vaibhavgautam.lightweight', 'appium:noReset': true, 'appium:processArguments': { args: ['--today', '2026-08-27'] },
  'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const attrs = (s) => Object.fromEntries([...s.matchAll(/(\w+)="([^"]*)"/g)].map(m => [m[1], m[2]]));
const show = async (tag) => {
  const src = await driver.getPageSource();
  const rows = [...src.matchAll(/<XCUIElementType(\w+)([^>]*)>/g)].map(m => [m[1], attrs(m[2])]).filter(([t, a]) => (a.name || a.label) && !/Application|Window/.test(t));
  console.log(`--- ${tag}: ${rows.length} named`);
  for (const [t, a] of rows.slice(0, 40)) console.log(`${t.padEnd(12)} name=${(a.name||'').slice(0,26).padEnd(26)} label=${(a.label||'').slice(0,22).padEnd(22)} @${a.x},${a.y} ${a.width}x${a.height} vis=${a.visible}`);
};
const tap = async (x, y) => { await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [ { type: 'pointerMove', duration: 0, x, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 60 }, { type: 'pointerUp', button: 0 } ] }]); await driver.releaseActions(); };
await sleep(800); await show('home');
const win = await driver.getWindowSize(); console.log('window', JSON.stringify(win));
const el = await driver.$('~tab.workouts'); console.log('tab.workouts exists:', await el.isExisting(), await el.isExisting() ? JSON.stringify({ ...(await el.getLocation()), ...(await el.getSize()) }) : '');
await el.click(); await sleep(900); await driver.saveScreenshot('./shots/dbg-after-elclick.png');
const s1 = await driver.$('~tab.home'); console.log('after element click, Workouts title present:', await driver.$('-ios predicate string:label == "WORKOUTS"').isExisting());
await tap(Math.round(win.width * 0.605), Math.round(win.height * 0.605)); await sleep(900); await driver.saveScreenshot('./shots/dbg-after-coordtap.png');
console.log('after coord tap, WORKOUTS present:', await driver.$('-ios predicate string:label == "WORKOUTS"').isExisting());
await show('now');
await driver.deleteSession();
