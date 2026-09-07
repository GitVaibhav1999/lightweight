import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const id = (s) => driver.$(`~${s}`);
const shot = (n) => driver.saveScreenshot(`${SC}/${n}.png`);
await sleep(600);
if (await id('home.resume').isExisting()) { await id('home.resume').click(); await sleep(1400); }
else if (await id('home.start').isExisting()) { await id('home.start').click(); await sleep(4200); }   // splash then session
await id('rest.chip').waitForExist({ timeout: 10000 });
await shot('chip-idle');                                   // should read ▶ REST 1:30
await id('rest.chip').click(); await sleep(900);
if (!(await id('rest.screen').isExisting())) { await id('rest.chip').click(); await sleep(900); }  // it was running: that tap cancelled it
await shot('rest-glass');                                  // countdown + session readable behind
await id('rest.continue').click(); await sleep(600);
await shot('rest-dismissed');
console.log('chip label:', await id('rest.chip').getAttribute('label'), '| screen still up:', await id('rest.screen').isExisting());
await driver.deleteSession();
