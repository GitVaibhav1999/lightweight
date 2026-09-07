import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
await sleep(600);
if (!(await id('live.pill').isExisting())) {          // start something so there is a minimised workout
  if (await id('home.start').isExisting()) { await id('home.start').click(); await sleep(2800); }
  if (await id('session.minimize').isExisting()) { await id('session.minimize').click(); await sleep(1200); }
  else { await driver.execute('mobile: swipe', { direction: 'down' }); await sleep(1200); }
}
await sleep(500);
await driver.saveScreenshot(`${SC}/min-row.png`);
console.log('pill present:', await id('live.pill').isExisting());
await driver.deleteSession();
