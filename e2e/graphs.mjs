import { remote } from 'webdriverio';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:processArguments': { args: ['--today', '2026-08-27'] }, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const shot = (n) => driver.saveScreenshot(`./shots/g-${n}.png`);
await driver.$('~workout.card').waitForExist({ timeout: 15000 }); await sleep(500);
// open each workout card's summary (each has its own progression chart)
const cards = await driver.$$('~workout.card');
for (let i = 0; i < Math.min(cards.length, 4); i++) {
  const cs = await driver.$$('~workout.card'); await cs[i].click();
  await driver.$('~summary.done').waitForExist({ timeout: 8000 }); await sleep(600);
  await shot(`summary-${i}`);
  await driver.$('~summary.done').click(); await sleep(600);
}
await driver.deleteSession();
