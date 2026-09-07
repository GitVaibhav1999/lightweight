import { remote } from 'webdriverio';
const driver = await remote({
  hostname: '127.0.0.1', port: 4723, path: '/',
  capabilities: {
    platformName: 'iOS', 'appium:automationName': 'XCUITest',
    'appium:udid': '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80',
    'appium:bundleId': 'com.vaibhavgautam.lightweight',
    'appium:processArguments': { args: ['--today','2026-08-27','--coach-fixture'] },
    'appium:noReset': true, 'appium:wdaLaunchTimeout': 120000,
  },
});
const fs = await import('fs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
const tap = async (x, y, hold = 60) => driver.performActions([{ type: 'pointer', id: 'p'+Math.floor(x), parameters: { pointerType: 'touch' }, actions: [
  { type: 'pointerMove', duration: 0, x, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: hold }, { type: 'pointerUp', button: 0 }] }]);
const swipeH = (from, to) => driver.execute('mobile: dragFromToForDuration', { duration: 0.25, fromX: from, fromY: 500, toX: to, toY: 500 });
try {
  await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
  await sleep(1200);   // launchApp does NOT terminate a running instance — a leftover --empty-demo process masquerades as wiped data
  await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: ['--today','2026-08-27','--coach-fixture'] });
  await sleep(3000);
  if (!(await driver.$('~routine.hero').isExisting())) { console.log('NO DATA — ABORT TAKE'); process.exit(2); }
  // 1. insight: collapse → expand (border sweep on camera)
  const panel = await driver.$('~coach.insight');
  if (await panel.isExisting()) {
    const loc = await panel.getLocation();
    await tap(200, Math.round(loc.y + 22)); await sleep(900);      // collapse to spine
    await tap(200, Math.round(loc.y + 22)); await sleep(2200);     // expand + sweep
  }
  // 2. slide to start → splash (grab still mid-flash)
  const knob = await driver.$('~slide.start');
  const kl = await knob.getLocation(); const ks = await knob.getSize();
  const ky = Math.round(kl.y + ks.height / 2);
  await driver.performActions([{ type: 'pointer', id: 's', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: Math.round(kl.x + 45), y: ky },
    { type: 'pointerDown', button: 0 },
    { type: 'pointerMove', duration: 450, x: Math.round(kl.x + ks.width - 25), y: ky },
    { type: 'pointerUp', button: 0 }] }]);
  await sleep(150);
  fs.writeFileSync('/tmp/splash-real.png', Buffer.from(await driver.takeScreenshot(), 'base64'));
  await sleep(2500);
  // 3. mark two sets
  const circles = await driver.$$('-ios predicate string:name BEGINSWITH "set."');
  for (const c of circles.slice(0, 2)) { try { await c.click(); await sleep(700); } catch {} }
  await sleep(800);
  // 4. minimize to pill
  const min = await driver.$('~session.minimize');
  if (await min.isExisting()) { await min.click(); } else { await tap(45, 165); }   // chevron top-left
  await sleep(1500);
  // 5. theme reveal: long-press logo → light
  const logo = await driver.$('~home.logo');
  const ll = await logo.getLocation(); const ls = await logo.getSize();
  const hold = () => driver.performActions([{ type: 'pointer', id: 'lp', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x: Math.round(ll.x + ls.width / 2), y: Math.round(ll.y + ls.height / 2) },
    { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 800 }, { type: 'pointerUp', button: 0 }] }]);
  await hold(); await sleep(2200);        // light reveal
  await hold(); await sleep(2000);        // back to dark
  // 6. workouts → calendar
  await swipeH(360, 40); await sleep(1400);
  await swipeH(360, 40); await sleep(1200);
  await driver.execute('mobile: swipe', { direction: 'up' }); await sleep(1600);
  console.log('WALKTHROUGH DONE');
} finally { await driver.deleteSession().catch(() => {}); }
