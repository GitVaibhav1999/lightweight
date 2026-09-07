import { remote } from 'webdriverio';
const driver = await remote({
  hostname: '127.0.0.1', port: 4723, path: '/',
  capabilities: {
    platformName: 'iOS', 'appium:automationName': 'XCUITest',
    'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80',
    'appium:bundleId': 'com.vaibhavgautam.lightweight',
    'appium:wdaLaunchTimeout': 120000,
  },
});
const fs = await import('fs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const shot = async n => fs.writeFileSync(`/tmp/sb-${n}.png`, Buffer.from(await driver.takeScreenshot(), 'base64'));
try {
  await driver.execute('mobile: pressButton', { name: 'home' }); await sleep(1000);
  await driver.updateSettings({ defaultActiveApplication: 'com.apple.springboard' });
  await driver.performActions([{ type: 'pointer', id: 'lp', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: 200, y: 600 }, { type: 'pointerDown', button: 0 },
    { type: 'pause', duration: 1500 }, { type: 'pointerUp', button: 0 }] }]);
  await sleep(1200); await shot('jiggle');
  const edit = await driver.$('~Edit');
  if (await edit.isExisting()) {
    await edit.click(); await sleep(800);
    const add = await driver.$('-ios predicate string:label == "Add Widget"');
    if (await add.isExisting()) { await add.click(); }
  }
  await sleep(1500); await shot('gallery');
  const search = await driver.$('-ios predicate string:type == "XCUIElementTypeSearchField"');
  await search.click(); await sleep(500);
  await search.setValue('Light Weight'); await sleep(1200); await shot('search');
  const row = await driver.$('-ios predicate string:label CONTAINS "Light Weight"');
  await row.click(); await sleep(1200); await shot('picker');
  for (let i = 0; i < 3; i++) {
    const title = await driver.$('-ios predicate string:label == "Training Year"');
    if (await title.isExisting()) break;
    await driver.execute('mobile: swipe', { direction: 'left' }); await sleep(700);
  }
  await shot('year-page');
  const addBtn = await driver.$('-ios predicate string:label CONTAINS "Add Widget"');
  await addBtn.click(); await sleep(1200);
  await driver.execute('mobile: pressButton', { name: 'home' }); await sleep(1500);
  await shot('home-final');
  console.log('WIDGET ADDED');
} catch (e) { console.log('FAILED:', e.message); try { await shot('fail'); } catch {} }
finally { await driver.deleteSession().catch(() => {}); }
