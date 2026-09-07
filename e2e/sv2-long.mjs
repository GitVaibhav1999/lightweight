import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
await sleep(600);
await driver.$('~nav.tab.workouts').click(); await sleep(900);
const long = await driver.$('-ios predicate string:name CONTAINS "Shoulder Dominating"');
if (await long.isExisting()) { await long.click(); await sleep(1000); await driver.saveScreenshot(`${SC}/longname-fixed.png`); console.log('captured'); }
else { console.log('no long-named workout on this page'); await driver.saveScreenshot(`${SC}/longname-fixed.png`); }
await driver.deleteSession();
