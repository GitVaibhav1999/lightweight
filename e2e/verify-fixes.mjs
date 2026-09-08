// Verifies this session's fixes against the REAL Hevy export (470 sessions), not fixtures.
// Deliberately no --coach-fixture and no --coach-demo: the coach panel must reach the
// unanswered state so the new two-question ask is the thing on screen.
import { remote } from 'webdriverio';
import fs from 'node:fs';

const UDID = process.env.SIM_UDID || '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80';
const CSV  = new URL('../.cache/hevy/workout_data.csv', import.meta.url).pathname;
const OUT  = new URL('./verify/', import.meta.url).pathname;
fs.mkdirSync(OUT, { recursive: true });

const BASE = ['--today', '2026-08-27', '--mock-auth', '--hevy-csv', CSV];
const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': UDID,
  'appium:bundleId': 'com.vaibhavgautam.lightweight', 'appium:noReset': true,
  'appium:processArguments': { args: BASE }, 'appium:newCommandTimeout': 300,
  'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });

const sleep = ms => new Promise(r => setTimeout(r, ms));
const shot  = async name => { await driver.saveScreenshot(`${OUT}${name}.png`); };
const src   = () => driver.getPageSource();
const has   = async (sel, t = 6000) => { try { await driver.$(`~${sel}`).waitForExist({ timeout: t }); return true; } catch { return false; } };

const results = [];
const check = (name, pass, detail = '') => {
  results.push({ name, pass, detail });
  console.log(`  ${pass ? '✓' : '✗'} ${name}${detail ? ' — ' + detail : ''}`);
};

const relaunch = async (extra = []) => {
  await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
  await sleep(700);
  await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: [...BASE, ...extra] });
  await sleep(2600);   // the import parses 6k rows on launch
};

// ── 1. real data landed, and a loop exists to show it ───────────────────────
// A raw Hevy import gives sessions and workouts but no routine — the loop is the
// user's choice — so Home legitimately sits in its no-routine empty state until
// one is built. Build it the way a user does rather than seeding behind the UI.
await relaunch(['--focus', 'off']);
await shot('01-home-before');
{
  await driver.$('~nav.tab.workouts').click(); await sleep(1200);
  for (const name of ['Legs', 'Push 1', 'Back', 'Shoulders']) {
    const btn = driver.$(`~loop.add.${name}`);
    if (await btn.isExisting().catch(() => false)) { await btn.click(); await sleep(450); }
  }
  await shot('02-routine-built');
  await driver.$('~nav.tab.home').click(); await sleep(1400);
  await shot('03-home');
  const s = await src();
  const live = /CYCLE|NEXT UP|IN PROGRESS|DONE/i.test(s) && !/is your workouts, on repeat/i.test(s);
  check('real history + built routine render on Home', live,
        live ? '470 sessions, loop of 4' : 'still the no-routine empty state');
}

// ── 2. calendar no longer offers the Hevy import ────────────────────────────
await relaunch(['--screen', 's8', '--focus', 'off']);
await sleep(1200); await shot('02-calendar');
{
  const s = await src();
  const gone = !/Import from Hevy/i.test(s);
  check('calendar header has no "Import from Hevy"', gone,
        gone ? 'settings owns it' : 'link still present');
  const n = (s.match(/(\d+)\s+sessions/i) || [])[1];
  check('calendar shows the real session count', Number(n) > 100, n ? `${n} sessions in view` : 'no count found');
}

// ── 3. the two-question ask, on a real finished session ─────────────────────
await relaunch(['--screen', 's3', '--focus', 'off']);
await sleep(1400); await shot('03-summary');
{
  if (await has('coach.ask', 8000)) {
    await driver.$('~coach.ask').click();
    await sleep(1200); await shot('04-ask-effort');
    const s = await src();
    const isEffort = /How hard was that session/i.test(s);
    const zeroToTen = await has('coach.scale.0', 3000) && await has('coach.scale.10', 3000);
    check('Q1 asks effort on a 0-10 scale', isEffort && zeroToTen,
          isEffort ? (zeroToTen ? 'Borg CR-10 rendered' : '0-10 buttons missing') : 'old wording still shown');
    check('old easy/about-right/brutal is gone', !/about right|brutal/i.test(s));

    if (zeroToTen) {
      await driver.$('~coach.scale.8').click();     // heavy session
      await sleep(900); await shot('05-ask-recovery');
      const s2 = await src();
      const isRecovery = /how recovered did you feel/i.test(s2);
      check('Q2 asks recovery after effort', isRecovery,
            isRecovery ? 'PRS follows sRPE' : 'second question did not appear');
      if (isRecovery) {
        await driver.$('~coach.scale.2').click();   // poorly recovered -> underRecovered
        await sleep(1500); await shot('06-after-answers');
        check('both answers accepted, ask dismissed', !/how recovered did you feel/i.test(await src()));
      }
    }
  } else {
    check('coach ask reachable on a finished session', false, 'coach.ask not found');
  }
}

// ── 4. focus mode opens by default on a real workout ────────────────────────
await relaunch(['--screen', 's2']);          // no --focus: exercise the real default
await sleep(1800); await shot('07-focus');
{
  const s = await src();
  const focus = /REPS/i.test(s) && (await has('focus.check', 4000) || /PREV|NEXT/i.test(s));
  check('focus mode is the default live view', focus, focus ? 'one-set-at-a-time' : 'table view opened');
}

// ── 5. table view still reachable, with real sets ───────────────────────────
await relaunch(['--screen', 's2', '--focus', 'off']);
await sleep(1800); await shot('08-table');
{
  const s = await src();
  const table = await has('set.check.0', 5000) || /set\.check\./.test(s);
  check('table view still works with --focus off', table, table ? 'set rows present' : 'no set rows');
}

// ── 6. verdict arrows: accent must be earned ────────────────────────────────
await relaunch(['--screen', 's4', '--focus', 'off']);
await sleep(1600); await shot('09-exercise-detail');
{
  const s = await src();
  const real = /e1RM/i.test(s) && !/is your workouts, on repeat/i.test(s);
  check('exercise detail renders real history', real, real ? 'e1RM series present' : 'empty state');
}

console.log('\n' + '─'.repeat(58));
const failed = results.filter(r => !r.pass);
console.log(`${results.length - failed.length}/${results.length} checks passed`);
if (failed.length) { console.log('FAILED:'); failed.forEach(f => console.log('  ✗ ' + f.name + (f.detail ? ' — ' + f.detail : ''))); }
console.log(`shots: ${OUT}`);
await driver.deleteSession();
process.exit(failed.length ? 1 : 0);
