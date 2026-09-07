import { remote } from 'webdriverio';
const SC = '/private/tmp/claude-503/-Users-vaibhavkumar-Documents-Workspace/32706fa7-a281-4158-8cb5-4a1fb6aaa370/scratchpad';
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80', 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:newCommandTimeout': 300, 'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
await sleep(1500);
for (let step = 0; step < 8; step++) {
  await driver.saveScreenshot(`${SC}/ob-${step}.png`);
  const btns = await driver.$$('//XCUIElementTypeButton');
  const labels = [];
  for (const b of btns) { const l = await b.getAttribute('label').catch(() => ''); if (l) labels.push(l); }
  console.log(`step ${step}: ${labels.slice(0, 10).join(' | ')}`);
  // prefer an obvious forward action
  const want = ['Continue', 'Next', 'Get started', 'Start', 'Use these', 'Done', 'Build my routine', 'Create routine'];
  let clicked = false;
  for (const w of want) {
    const b = await driver.$(`-ios predicate string:label CONTAINS[c] "${w}"`);
    if (await b.isExisting()) { await b.click(); clicked = true; console.log(`  -> clicked "${w}"`); break; }
  }
  if (!clicked) { console.log('  (no forward button found)'); break; }
  await sleep(1400);
  if (await driver.$('~home.start').isExisting() || await driver.$('~routine.hero').isExisting()) { console.log('reached home'); break; }
}
await driver.deleteSession();
