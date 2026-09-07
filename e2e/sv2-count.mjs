import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
await sleep(700);
await driver.$('~nav.tab.calendar').click(); await sleep(1200);
for (let i = 0; i < 8; i++) { await driver.execute('mobile: swipe', { direction: 'up' }); await sleep(300); }
const e = await driver.$('-ios predicate string:label CONTAINS "All history"');
console.log('header:', await e.isExisting() ? await e.getAttribute('label') : 'NOT FOUND');
const streak = await driver.$('~calendar.streak');
console.log('streak:', await streak.isExisting() ? await streak.getAttribute('label') : 'n/a');
await driver.deleteSession();
