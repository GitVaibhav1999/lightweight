import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:processArguments': { args: ['--today', '2026-08-27'] }, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const attrs = (s) => Object.fromEntries([...s.matchAll(/(\w+)="([^"]*)"/g)].map(m => [m[1], m[2]]));
const named = async () => { const src = await driver.getPageSource(); return [...src.matchAll(/<XCUIElementType(\w+)([^>]*)>/g)].map(m => attrs(m[2]).name).filter(n => n && /^(page\.|header\.|slide\.|home\.|routine|picker|summary)/.test(n)).slice(0, 8); };
await sleep(1000); console.log('start:', await named());
await driver.execute('mobile: swipe', { direction: 'right' }); await sleep(900); await driver.saveScreenshot('./shots/dbg-swipe-right.png'); console.log('after swipe right:', await named());
await driver.execute('mobile: swipe', { direction: 'left' }); await sleep(900); console.log('after swipe left:', await named());
await driver.execute('mobile: swipe', { direction: 'left' }); await sleep(900); await driver.saveScreenshot('./shots/dbg-swipe-left2.png'); console.log('after 2nd swipe left:', await named());
// W3C slow drag as a real finger would
const s = await driver.getWindowSize(); const y = Math.round(s.height * 0.4);
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [ { type: 'pointerMove', duration: 0, x: Math.round(s.width*0.2), y }, { type: 'pointerDown', button: 0 }, { type: 'pointerMove', duration: 60, x: Math.round(s.width*0.3), y }, { type: 'pointerMove', duration: 300, x: Math.round(s.width*0.85), y }, { type: 'pointerUp', button: 0 } ] }]); await driver.releaseActions();
await sleep(900); console.log('after W3C drag right:', await named());
await driver.deleteSession();
