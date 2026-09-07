import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
await sleep(600);
await id('nav.tab.workouts').click(); await sleep(900);
await driver.saveScreenshot(`${SC}/wk-list.png`);
await driver.$('~routine.row').click(); await sleep(1000);            // normal tap → view mode
await driver.saveScreenshot(`${SC}/wk-view.png`);
console.log('view mode → Start present:', await id('workout.start').isExisting(), '| Save hidden:', !(await id('edit.save').isExisting()));
await id('edit.back').click(); await sleep(800);
await id('header.edit.toggle').click().catch(() => {});               // turn edit mode on if the toggle exists
await sleep(600);
await driver.saveScreenshot(`${SC}/wk-list-edit.png`);
await driver.deleteSession();
