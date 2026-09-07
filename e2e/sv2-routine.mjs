import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
await sleep(1200);
if (await id('nav.tab.workouts').isExisting()) { await id('nav.tab.workouts').click(); await sleep(900); }
await id('workouts.edit').click(); await sleep(800);                     // edit mode reveals loop.add.*
for (const name of ['Legs', 'Push 1', 'Back', 'Shoulders and biceps']) {
  const b = id(`loop.add.${name}`);
  if (await b.isExisting()) { await b.click(); await sleep(700); console.log(`added ${name}`); }
  else {
    for (let i = 0; i < 5 && !(await b.isExisting()); i++) { await driver.execute('mobile: swipe', { direction: 'up' }); await sleep(400); }
    if (await b.isExisting()) { await b.click(); await sleep(700); console.log(`added ${name} (after scroll)`); }
    else console.log(`MISSING ${name}`);
  }
}
await id('workouts.edit').click(); await sleep(900);
await driver.saveScreenshot(`${SC}/routine-built.png`);
await driver.deleteSession();
