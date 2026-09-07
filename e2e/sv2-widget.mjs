import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80',
  'appium:bundleId': 'com.apple.springboard', 'appium:noReset': true, 'appium:newCommandTimeout': 240, 'appium:wdaLaunchTimeout': 300000 } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
await sleep(1200);
const win = await driver.getWindowSize();
// long press empty home-screen area → jiggle mode
await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x: Math.round(win.width / 2), y: Math.round(win.height * 0.72) },
  { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 1600 }, { type: 'pointerUp', button: 0 } ] }]);
await driver.releaseActions(); await sleep(1800);
await driver.saveScreenshot(`${SC}/w1-jiggle.png`);
const edit = await driver.$('-ios predicate string:label == "Edit" OR label == "Add Widget" OR name == "Add Widget"');
if (await edit.isExisting()) { await edit.click(); await sleep(1200); await driver.saveScreenshot(`${SC}/w2-menu.png`);
  const addw = await driver.$('-ios predicate string:label == "Add Widget"');
  if (await addw.isExisting()) { await addw.click(); await sleep(1500); }
}
await driver.saveScreenshot(`${SC}/w3-gallery.png`);
const search = await driver.$('-ios predicate string:type == "XCUIElementTypeSearchField"');
if (await search.isExisting()) { await search.click(); await sleep(600); await driver.keys('Light Weight'); await sleep(1500); }
await driver.saveScreenshot(`${SC}/w4-search.png`);
console.log('gallery reached');
await driver.deleteSession();
