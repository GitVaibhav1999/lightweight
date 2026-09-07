import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
const box = async (s) => { const el = id(s); const l = await el.getLocation(), z = await el.getSize();
  return { x: l.x, y: l.y, w: z.width, h: z.height, right: l.x + z.width, bottom: l.y + z.height }; };
await sleep(400);
if (await id('live.pill').isExisting()) console.log('(session live — slider hidden)');
const slide = await box('slide.start'), plus = await box('nav.fresh');
const row = { x: 10, y: plus.y, right: plus.x - 12, bottom: plus.bottom };   // same HStack as the + circle
const win = await driver.getWindowSize();
console.log('slide :', JSON.stringify(slide));
console.log('navrow (derived):', JSON.stringify(row));
console.log('plus  :', JSON.stringify(plus));
console.log('--- vertical gap  slide→row :', Math.round(row.y - slide.bottom));
console.log('--- horizontal gap row→plus :', Math.round(plus.x - row.right));
console.log('--- left margin:', Math.round(row.x), '· right margin:', Math.round(win.width - plus.right), '· slide left:', Math.round(slide.x), 'right:', Math.round(win.width - slide.right));
await driver.deleteSession();
