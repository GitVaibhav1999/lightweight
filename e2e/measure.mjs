import { remote } from 'webdriverio';
const UDID = process.argv[2];
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': UDID, 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:processArguments': { args: ['--today', '2026-08-27'] }, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
await new Promise(r => setTimeout(r, 1500));
const win = await driver.getWindowSize();
const attrs = (s) => Object.fromEntries([...s.matchAll(/(\w+)="([^"]*)"/g)].map(m => [m[1], m[2]]));
const src = await driver.getPageSource();
const rows = [...src.matchAll(/<XCUIElementType(\w+)([^>]*)>/g)].map(m => [m[1], attrs(m[2])]);
const app = rows.find(([t]) => t === 'Application')?.[1], w = rows.find(([t]) => t === 'Window')?.[1];
console.log('window', JSON.stringify(win), '| app frame', app?.width + 'x' + app?.height, '| Window', w?.width + 'x' + w?.height);
for (const name of ['home.card', 'tab.home', 'slide.start', 'home.week', 'Thu 27 Aug']) {
  const r = rows.find(([, a]) => a.name === name)?.[1]; if (r) console.log(name.padEnd(12), `x=${r.x} w=${r.width} right=${+r.x + +r.width}  y=${r.y} h=${r.height}`);
}
await driver.deleteSession();
