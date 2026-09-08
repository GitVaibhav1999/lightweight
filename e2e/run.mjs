// LIGHT WEIGHT — Appium/XCUITest walkthrough. Waits for elements (and reports how long each transition took) and screenshots every state.
import { remote } from 'webdriverio';
import fs from 'node:fs';

const UDID = process.env.SIM_UDID || '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80';
const OUT = new URL('./shots/', import.meta.url).pathname; fs.mkdirSync(OUT, { recursive: true });
for (const f of fs.readdirSync(OUT)) if (/^\d\d-/.test(f)) fs.unlinkSync(OUT + f);

const driver = await remote({ hostname: '127.0.0.1', port: 4723, path: '/', logLevel: 'error', capabilities: {
  platformName: 'iOS', 'appium:automationName': 'XCUITest', 'appium:udid': UDID, 'appium:bundleId': 'com.vaibhavgautam.lightweight',
  'appium:noReset': true, 'appium:processArguments': { args: ['--today', '2026-08-27', '--coach-fixture', '--coach-demo', '--coach-fail-once', '--mock-auth', '--focus', 'off'] }, 'appium:newCommandTimeout': 300,
  'appium:wdaLaunchTimeout': 300000, 'appium:waitForQuiescence': false } });

// always start from a FRESH app process — and relaunch WITH the debug arguments:
// activateApp drops processArguments (lost --today AND --coach-fixture → live API calls + real dates!)
// --focus off: the switch is a sticky user preference and defaults ON, so every table step needs it pinned
const LAUNCH_ARGS = ['--today', '2026-08-27', '--coach-fixture', '--coach-demo', '--coach-fail-once', '--mock-auth', '--focus', 'off'];
await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
await new Promise(r => setTimeout(r, 800));
await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: LAUNCH_ARGS });
await new Promise(r => setTimeout(r, 1200));

const results = []; let n = 0;
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
const shot = async (name) => { n++; const f = `${OUT}${String(n).padStart(2, '0')}-${name}.png`; await driver.saveScreenshot(f); };
const id = (s) => driver.$(`~${s}`);
/** waits until the element exists AND its centre is inside the window horizontally (pager pages stay in the tree while off-screen) */
const onScreen = async (sel, timeout = 8000) => {
  const el = driver.$(`~${sel}`); await el.waitForExist({ timeout });
  const win = await driver.getWindowSize(); const t = Date.now();
  for (;;) {
    const l = await el.getLocation().catch(() => null); const sz = l && await el.getSize().catch(() => null);
    if (l && sz) { const cx = l.x + sz.width / 2; if (cx >= 0 && cx <= win.width) return el; }
    if (Date.now() - t > timeout) throw new Error(`~${sel} exists but is off-screen (x=${l && l.x})`);
    await sleep(200);
  }
};
const label = (s) => driver.$(`-ios predicate string:label == "${s}"`);
/** click `sel`, then wait for `expect` to exist; returns ms it took */
const go = async (sel, expect, timeout = 8000) => { const t = Date.now(); await sel.click(); await expect.waitForExist({ timeout }); return Date.now() - t; };
const ONLY = process.argv.slice(2).filter(a => !a.startsWith('-'));   // focused run: node run.mjs nav-bar minimize
const step = async (name, fn) => { if (ONLY.length && !ONLY.includes(name)) return; const t = Date.now(); try { const info = await fn(); results.push([name, 'ok', Date.now() - t, info]); } catch (e) { results.push([name, 'FAIL', Date.now() - t, (e.message || String(e)).split('\n')[0].slice(0, 120)]); await shot(`fail-${name}`); } };
const rect = async (el) => { const l = await el.getLocation(), s = await el.getSize(); return { x: l.x, y: l.y, w: s.width, h: s.height }; };
/** reorder drag: stepped 8px moves — a single smooth pointerMove can glitch at the drop boundary and never commit */
let nextBefore = '';
const rowDrag = async (x, y, dy) => {
  const n = Math.ceil(Math.abs(dy) / 8), st = dy / n;
  const steps = Array.from({ length: n }, (_, i) => ({ type: 'pointerMove', duration: 80, x, y: Math.round(y + st * (i + 1)) }));
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 160 },
    ...steps, { type: 'pause', duration: 180 }, { type: 'pointerUp', button: 0 } ] }]); await driver.releaseActions(); };
const drag = async (el, ms = 700, rev = false) => { const r = await rect(el); const y = Math.round(r.y + r.h / 2); const x1 = Math.round(r.x + r.w * (rev ? 0.92 : 0.08)), x2 = Math.round(r.x + r.w * (rev ? 0.01 : 0.99));
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [ { type: 'pointerMove', duration: 0, x: x1, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 }, { type: 'pointerMove', duration: ms, x: x2, y }, { type: 'pause', duration: 150 }, { type: 'pointerUp', button: 0 } ] }]); await driver.releaseActions(); };
/** swipe-up-to-start: drag the handle up by `frac` of the screen, then release */
const pullUp = async (el, frac = 0.78) => {
  const r = await rect(el); const win = await driver.getWindowSize();
  const x = Math.round(r.x + r.w / 2), y0 = Math.round(r.y + r.h / 2);
  const y1 = Math.max(8, Math.round(y0 - win.height * frac));
  const steps = Array.from({ length: 8 }, (_, i) => ({ type: 'pointerMove', duration: 55, x, y: Math.round(y0 + (y1 - y0) * (i + 1) / 8) }));
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x, y: y0 }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 90 },
    ...steps, { type: 'pause', duration: 140 }, { type: 'pointerUp', button: 0 } ] }]);
  await driver.releaseActions();
};
const swipeX = async (dir) => { const s = await driver.getWindowSize(); const y = Math.round(s.height * 0.45); const x1 = Math.round(s.width * (dir === 'left' ? 0.85 : 0.15)), x2 = Math.round(s.width * (dir === 'left' ? 0.15 : 0.85));
  await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [ { type: 'pointerMove', duration: 0, x: x1, y }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 40 }, { type: 'pointerMove', duration: 220, x: x2, y }, { type: 'pointerUp', button: 0 } ] }]); await driver.releaseActions(); };
const swipeTo = async (dir, expect, timeout = 8000) => { const t = Date.now(); await driver.execute('mobile: swipe', { direction: dir }); await expect.waitForExist({ timeout }); return Date.now() - t; };
/** swipe until `sel` is on-screen — the native swipe occasionally doesn't register, so retry up to 3 times */
const swipeUntil = async (dir, sel) => {
  const t = Date.now();
  for (let i = 0; i < 3; i++) {
    await driver.execute('mobile: swipe', { direction: dir });
    try { await onScreen(sel, 2600); return Date.now() - t; } catch {}
  }
  await onScreen(sel, 3000); return Date.now() - t;
};
/** Toggle edit only when needed — blind toggles invert leaked state and cascade failures. */
const ensureEdit = async (on) => {
  const t = id('workouts.edit');
  const editing = /Done editing/.test(await t.getAttribute('label'));
  if (editing !== on) { await t.click(); await sleep(450); }
};
/** scroll the page until the button is present AND vertically in view, then tap it */
const tapInList = async (sel, tries = 5) => {
  const win = await driver.getWindowSize();
  for (let i = 0; i < tries; i++) {
    const el = driver.$(`~${sel}`);
    if (await el.isExisting().catch(() => false)) {
      const l = await el.getLocation().catch(() => null);
      if (l && l.y > 90 && l.y < win.height - 110) { await el.click(); return true; }
    }
    await driver.execute('mobile: swipe', { direction: 'up' }); await sleep(450);
  }
  throw new Error(`~${sel} never came into view`);
};
const swipeUp = async () => { const s = await driver.getWindowSize(); await driver.execute('mobile: dragFromToForDuration', { duration: 0.4, fromX: s.width / 2, fromY: s.height * 0.8, toX: s.width / 2, toY: s.height * 0.2 }); };

await step('cleanup-live', async () => {
  await sleep(600);
  if (await id('home.resume').isExisting()) {
    await id('home.resume').click(); await id('slide.finish').waitForExist({ timeout: 8000 }); await sleep(400);
    await drag(id('slide.finish')); await sleep(700);
    if (!(await id('summary.done').isExisting()) && await id('slide.finish').isExisting()) { await drag(id('slide.finish')); }  // armed pill: second slide
    await id('summary.done').waitForExist({ timeout: 8000 }); await sleep(300);
    await id('summary.done').click(); await sleep(700);
    return 'stale live session finished';
  }
  return 'clean';
});
await step('app-icon', async () => {
  const { execSync } = await import('node:child_process');
  const app = execSync(`xcrun simctl get_app_container ${UDID} com.vaibhavgautam.lightweight app`).toString().trim();
  const plist = execSync(`plutil -p "${app}/Info.plist"`).toString();
  if (!fs.existsSync(`${app}/Assets.car`) || !plist.includes('CFBundleIcons')) throw new Error('app icon not compiled into bundle');
  return 'Assets.car + CFBundleIcons present';
});
await step('home', async () => { await id('home.start').waitForExist({ timeout: 20000 }); await onScreen('home.start', 8000); await onScreen('routine.hero'); await driver.$('-ios predicate string:label CONTAINS[c] "CYCLE BEST"').waitForExist({ timeout: 4000 }); await sleep(600); await shot('home'); });
await step('nav-bar', async () => {
  await id('nav.tab.calendar').click(); await onScreen('calendar.streak', 6000); await sleep(300);
  await id('nav.tab.home').click(); await onScreen('routine.hero', 6000); await sleep(300);
  return 'tabs page: calendar + home';
});
await step('start-sheet', async () => { const t = Date.now();
  await id('nav.tab.workouts').click(); await sleep(800);
  await id('workouts.empty.session').waitForExist({ timeout: 8000 });
  await id('workouts.empty.session').click(); await sleep(700);
  await id('start.fresh').waitForExist({ timeout: 4000 });
  await shot('start-sheet');
  await id('start.fresh').click();
  await id('slide.finish').waitForExist({ timeout: 8000 }); await sleep(400);
  await go(id('+ Add exercise'), id('picker.search'));
  const f = id('picker.search'); await f.click(); await f.setValue('bench'); await sleep(500);
  await driver.$('-ios predicate string:label CONTAINS "Bench Press (Barbell)"').click();
  await id('slide.finish').waitForExist({ timeout: 8000 }); await sleep(400); await shot('fresh-session');
  await drag(id('slide.finish')); await sleep(700);
  if (!(await id('summary.done').isExisting()) && await id('slide.finish').isExisting()) { await drag(id('slide.finish')); }  // unchecked fresh sets arm the pill
  await id('summary.done').waitForExist({ timeout: 8000 }); await go(id('summary.done'), id('home.start')); return `${Date.now() - t}ms`; });
await step('coach-grain', async () => {
  if (!(await id('coach.insight').isExisting())) {
    await id('coach.insight.ask').waitForExist({ timeout: 8000 });
    await id('coach.insight.ask').click(); await sleep(800);
  }
  await id('coach.insight').waitForExist({ timeout: 8000 });
  if (!(await id('coach.insight.body').isExisting())) { await id('coach.insight').click(); await sleep(400); }
  await id('coach.insight.body').waitForExist({ timeout: 3000 });
  await id('coach.insight.change.0').waitForExist({ timeout: 2000 });
  await shot('coach-home');
  const insight = await id('coach.insight').getAttribute('label');
  if (/[—–]/.test(insight || '')) throw new Error('em dash leaked into coach text');
  return 'insight renders · no em dashes';
});
await step('workouts', async () => { const ms = await swipeUntil('left', 'page.workouts'); await sleep(400);
  const h = await rect(id('header.workouts')); const t = await rect(id('page.workouts'));
  const gap = Math.round(t.y - h.y - h.h);
  await shot('workouts');
  if (gap > 22 || gap < 0) throw new Error(`header-to-content gap ${gap}pt (want 0…22)`);
  return `swipe ${ms}ms · gap ${gap}pt`; });
await step('loop-add', async () => {
  const rows = async () => [...(await driver.getPageSource()).matchAll(/Button[^>]*name="routine.row"/g)].length;
  await ensureEdit(true);                     // + add lives in edit mode only
  const before = await rows();
  const btn = driver.$('-ios predicate string:name BEGINSWITH "loop.add."');
  await btn.waitForExist({ timeout: 4000 }); await btn.click(); await sleep(500);
  const after = await rows();
  if (after !== before + 1) throw new Error(`loop did not grow (${before} → ${after})`);
  await id(`routine.remove.${after - 1}`).click(); await sleep(400);       // restore
  await ensureEdit(false);
  if ((await rows()) !== before) throw new Error('restore failed');
  return `${before} → ${after} → ${before} (edit-gated)`;
});
await step('slot-repeat', async () => {
  const rows = async () => [...(await driver.getPageSource()).matchAll(/Button[^>]*name="routine.row"/g)].length;
  await id('nav.tab.workouts').click(); await onScreen('page.workouts', 6000); await sleep(400);
  await ensureEdit(true);                     // + Add slot lives in edit mode only
  const src = await driver.getPageSource();
  const already = /name="routine.row"[^>]*label="([^"]+)"/.exec(src)[1];   // a workout ALREADY in the loop
  const before = await rows();
  await id('slot.add').click(); await sleep(600);
  await onScreen('slot.picker', 6000);
  const pick = driver.$(`~slot.pick.${already}`);
  for (let i = 0; i < 4 && !(await pick.isExisting()); i++) { await driver.execute('mobile: swipe', { direction: 'up' }); await sleep(400); }
  await pick.click(); await sleep(800);       // picking one already in the loop just appends another slot
  const after = await rows();
  const also = await id('routine.also.0').isExisting();      // the repeat marks where else it takes a turn
  await shot('routine-slots');
  await tapInList(`routine.remove.${after - 1}`); await sleep(500);         // restore — a long loop pushes it below the fold
  await ensureEdit(false);
  if (after !== before + 1) throw new Error(`slot not appended (${before} → ${after})`);
  if (!also) throw new Error('repeated slot carries no "also" marker');
  if ((await rows()) !== before) throw new Error('restore failed');
  return `${already} took slot ${after} · also marker · removed`;
});
await step('slot-ordinals', async () => {
  await id('nav.tab.home').click(); await onScreen('routine.hero', 6000); await sleep(500);
  const tags = [...(await driver.getPageSource()).matchAll(/<[^>]*name="slot\.label\.\d+"[^>]*>/g)].map(m => m[0]);
  if (!tags.length) throw new Error('no slot labels under the hero');
  const labels = tags.map(t => (/label="([^"]*)"/.exec(t) || [, ''])[1]);
  // ordinals are additive: a label carries a turn if and only if that workout fills two slots
  const byName = {};
  tags.forEach((t, i) => { (byName[labels[i]] = byName[labels[i]] || []).push(t); });
  for (const [name, ts] of Object.entries(byName)) {
    const repeated = ts.length > 1;
    for (const t of ts) if (/value="turn/.test(t) !== repeated) throw new Error(`${name}: ordinal ${repeated ? 'missing on' : 'without'} a repeat`);
  }
  await id('nav.tab.workouts').click(); await onScreen('page.workouts', 6000); await sleep(400);
  return labels.join(' · ');
});
await step('workout-delete', async () => {
  await go(id('+ New workout'), id('edit.back')); await sleep(300);           // create
  await go(id('edit.back'), id('page.workouts')); await sleep(300);
  await ensureEdit(true);                         // edit mode
  await driver.$('-ios predicate string:label CONTAINS[c] "editing"').waitForExist({ timeout: 3000 });   // header swaps text
  const count = async () => (await driver.$$('-ios predicate string:name == "delete.New workout"')).length;
  const beforeDel = await count();
  const trash = driver.$('-ios predicate string:name == "delete.New workout"');
  await trash.waitForExist({ timeout: 4000 }); await trash.click(); await sleep(400);
  await id('delete.confirm').waitForExist({ timeout: 3000 });                  // inline red Delete, no popup
  await id('delete.confirm').click(); await sleep(500);
  const gone = (await count()) < beforeDel;   // residue-proof: assert the count dropped
  await ensureEdit(false);
  if (!gone) throw new Error('workout not deleted');
  return 'created → armed → inline deleted';
});
await step('pin-workout', async () => {
  await ensureEdit(true);
  const pin = driver.$('-ios predicate string:name BEGINSWITH "pin."');
  await pin.waitForExist({ timeout: 4000 });
  const before = await pin.getAttribute('value');
  await pin.click(); await sleep(300);
  const after = await pin.getAttribute('value');
  if (before === after) throw new Error(`pin state did not toggle (${before})`);
  if (after !== 'pinned') { await pin.click(); await sleep(300); }   // end state: pinned → calendar can assert index charts
  await ensureEdit(false);
  return `${before} → pinned (kept for calendar)`;
});
await step('routine-reorder', async () => {
  await ensureEdit(true);
  await driver.execute('mobile: swipe', { direction: 'down' }); await sleep(500);   // routine rows to the top
  const rows = async () => [...(await driver.getPageSource()).matchAll(/Button[^>]*name="routine.row"[^>]*label="([^"]+)"/g)].map(m => m[1]).slice(0, 2);
  const dragDown = async () => { const h = id('handle.0'); const r = await rect(h); await rowDrag(Math.round(r.x + r.w / 2), Math.round(r.y + r.h / 2), 56); await sleep(600); };
  const before = await rows();
  let after = before;
  for (let i = 0; i < 4 && before[0] === after[0]; i++) { await dragDown(); after = await rows(); }
  await shot('routine-reordered');
  if (before[0] === after[0]) throw new Error(`order unchanged: ${after.join(' → ')}`);
  // put it back so the loop pointer stays on the same workout for the rest of the run — verify, retry once
  const putBackUp = async () => { const h = id('handle.1'); const r = await rect(h); await rowDrag(Math.round(r.x + r.w / 2), Math.round(r.y + r.h / 2), -56); await sleep(500); };
  const putBackDown = async () => { const h = id('handle.0'); const r = await rect(h); await rowDrag(Math.round(r.x + r.w / 2), Math.round(r.y + r.h / 2), 56); await sleep(500); };
  await putBackUp(); let mode = 'up';                       // exercise the up-drag; recover with down-drags if synthesis flakes
  if ((await rows())[0] !== before[0]) { mode = 'up-failed,down'; for (let i = 0; i < 4 && (await rows())[0] !== before[0]; i++) { await putBackDown(); } }
  if ((await rows())[0] !== before[0]) throw new Error(`put-back failed: ${(await rows()).join(' → ')}`);
  await ensureEdit(false);
  return `${before.join(' → ')}  ⇒  ${after.join(' → ')} · putback ${mode}`;
});
await step('workout-action', async () => {
  await id('nav.tab.workouts').click(); await sleep(700);
  await driver.$('~routine.row').click(); await sleep(900);
  const start = await id('workout.start').isExisting(), save = await id('edit.save').isExisting();
  await id('edit.back').click(); await sleep(600);
  if (!start || save) throw new Error(`view mode should show Start and hide Save (start=${start} save=${save})`);
  return 'view mode: Start shown · Save hidden';
});
await step('workout-edit', async () => {
  const legs = driver.$('-ios predicate string:name == "routine.row" AND label == "Legs"');
  const ms = await go(legs, id('+ Add exercise')); await sleep(300);
  await driver.$('-ios predicate string:label BEGINSWITH "Straight" OR label BEGINSWITH "Squat"').waitForExist({ timeout: 4000 });
  await shot('workout-edit'); return `${ms}ms`;
});
await step('reorder', async () => {
  const first = await driver.$('-ios predicate string:label BEGINSWITH "Straight" OR label BEGINSWITH "Squat"').getText().catch(() => '');
  const h = id('handle.0'); const r = await rect(h); await rowDrag(Math.round(r.x + r.w / 2), Math.round(r.y + r.h / 2), 56);
  await sleep(600); await shot('reordered');
  const names = () => driver.getPageSource().then(src => [...src.matchAll(/StaticText[^>]*name="([^"]+)"/g)].map(m => m[1]).filter(n => /Deadlift|Squat|Leg Press|Press \(/.test(n)).slice(0, 2));
  const now = await names();
  if (now.length < 2) throw new Error('slot rows missing after reorder');
  if (now[0] === first) throw new Error(`slot order unchanged: ${now.join(' → ')}`);
  return `rows now: ${now.join(' → ')}`;
});
await step('slot-sheet', async () => { await driver.$('-ios predicate string:label BEGINSWITH "Straight" OR label BEGINSWITH "Squat"').click(); await label('Remove').waitForExist({ timeout: 4000 }); await sleep(300); await shot('slot-sheet'); });
await step('picker', async () => { const ms = await go(id('+ Add exercise'), id('picker.search')); await sleep(400); await shot('picker'); return `${ms}ms`; });
await step('picker-search', async () => { const f = id('picker.search'); await f.click(); await f.setValue('curl'); await sleep(700); await shot('picker-search'); await go(id('picker.cancel'), id('+ Add exercise')); });
await step('edit-back', async () => { const ms = await go(id('edit.back'), id('page.workouts')); return `${ms}ms`; });
await step('calendar', async () => { const ms = await swipeUntil('left', 'header.calendar'); await sleep(400);
  await id('calendar.streak').waitForExist({ timeout: 3000 }); await id('year.strip').waitForExist({ timeout: 2000 });
  await driver.$('-ios predicate string:label CONTAINS "· index"').waitForExist({ timeout: 4000 });   // pinned charts plot engine index
  await shot('calendar'); return `swipe ${ms}ms · index charts`; });
await step('calendar-scroll', async () => {
  await swipeUp(); await sleep(700); await shot('calendar-bottom');
  const win = await driver.getWindowSize();
  const ys = [...(await driver.getPageSource()).matchAll(/type="XCUIElementTypeStaticText"[^>]*y="(\d+)"[^>]*height="(\d+)"/g)]
    .map(m => Number(m[1]) + Number(m[2])).filter(b => b <= win.height + 2);   // only content actually visible on screen
  const maxY = Math.max(...ys);
  if (maxY < win.height - 40) throw new Error(`full-bleed regressed: visible content stops at ${maxY} (< ${win.height - 40})`);
  return `content reaches ${maxY}/${win.height}`;
});
await step('home-card', async () => { await swipeUntil('right', 'page.workouts'); await swipeUntil('right', 'routine.hero'); const card = await onScreen('workout.card'); const ms = await go(card, id('summary.done')); await sleep(400); await shot('summary-past'); return `${ms}ms`; });
await step('exercise-detail', async () => {
  const row = driver.$('-ios predicate string:label CONTAINS "×" AND type == "XCUIElementTypeButton"');
  let info = 'no exercise rows (empty session) — skipped detail';
  if (await row.isExisting()) { const ms = await go(row, id('exercise.back')); await sleep(400); await shot('exercise-detail'); await go(id('exercise.back'), id('summary.done')); info = `${ms}ms`; }
  await go(id('summary.done'), id('home.start')); return info;
});
await step('start-button', async () => { const t = Date.now();
  nextBefore = await id('home.start').getAttribute('label');
  await id('home.start').click();                                        // 10a: START lives in the NEXT UP card
  await sleep(320); await shot('splash');
  await id('slide.finish').waitForExist({ timeout: 8000 }); await sleep(600); await shot('session');
  return `${Date.now() - t}ms`; });
await step('check-sets', async () => {
  const pct = async () => (await id('session.progress').getText().catch(() => '?'));
  const before = await pct();
  await id('set.check.0').click(); await sleep(250); await id('set.check.1').click(); await sleep(500);
  const after = await pct();
  await shot('session-checked');
  if (before === after) throw new Error(`progress did not move (${before} → ${after})`);
  return `progress ${before} → ${after}`;
});
await step('session-v2', async () => {
  // reps stepper on an unchecked set: +1 solidifies the ghost
  const reps = async () => (await id('set.reps.0').getValue().catch(() => ''));   // ids repeat per exercise; $ takes the first block
  const r0 = await reps();
  await id('set.reps.plus.0').click(); await sleep(350);
  const r1 = await reps();
  if (r1 === r0) throw new Error(`stepper did not bump reps (${r0} -> ${r1})`);
  // + set: one more check circle appears
  const checks = async () => (await driver.$$('-ios predicate string:name BEGINSWITH "set.check."')).length;
  const c0 = await checks();
  await id('set.add').click(); await sleep(700);
  const c1 = await checks();
  if (c1 !== c0 + 1) throw new Error(`+ set did not add a row (${c0} -> ${c1})`);
  // rest chip: check-sets armed it; tap = cancel; tap again = quick-start; tap = cancel (leave idle for later steps)
  const chip = async () => (await id('rest.chip').getAttribute('label').catch(() => '?'));
  let lbl = await chip();
  if (lbl === 'REST') { await id('rest.chip').click(); await sleep(400); lbl = await chip(); }
  if (!/\d:\d\d/.test(lbl)) throw new Error(`chip not running: ${lbl}`);
  await id('rest.chip').click(); await sleep(400);
  lbl = await chip();
  if (lbl !== 'REST') throw new Error(`chip did not cancel: ${lbl}`);
  return `reps ${r0}->${r1} · +set ${c0}->${c1} · rest chip arms & cancels`;
});
await step('focus-switch', async () => {
  const parked = async () => (await id('focus.set').getAttribute('label'));
  await id('session.focus').click(); await sleep(600);
  await onScreen('focus.screen', 6000);
  await id('focus.weight').waitForExist({ timeout: 3000 });
  await sleep(300); await shot('focus-set');
  const kg = async () => (await id('focus.weight').getAttribute('value'));
  const k0 = await kg();
  await id('focus.weight.up').click(); await sleep(300);                 // chevrons step one unit
  const k1 = await kg();
  if (k0 === k1) throw new Error(`chevron did not step the weight (${k0})`);
  await id('focus.weight.down').click(); await sleep(300);
  const reps = async () => (await id('focus.reps').getAttribute('label'));
  const r0 = await reps();
  await id('focus.reps.plus').click(); await sleep(300);
  if ((await reps()) === r0) throw new Error(`stepper did not bump reps (${r0})`);
  await id('focus.reps.minus').click(); await sleep(250);
  const s0 = await parked();
  await id('focus.next').click(); await sleep(400);
  if ((await parked()) === s0) throw new Error(`NEXT did not move off ${s0}`);
  await id('focus.prev').click(); await sleep(400);
  if ((await parked()) !== s0) throw new Error(`PREV did not come back to ${s0}`);
  await id('session.focus').click(); await sleep(700);                   // and back to the table, same session
  await id('slide.finish').waitForExist({ timeout: 6000 });
  await id('set.check.0').waitForExist({ timeout: 3000 });
  return `${s0} · weight ${k0}→${k1} · reps ${r0} bumped · round trip`;
});
await step('focus-rest', async () => {
  await id('session.focus').click(); await sleep(600);
  await onScreen('focus.check', 6000);
  await id('focus.check').click(); await sleep(1200);
  if (await id('focus.newbest').isExisting()) {                          // the reward covers the rest state until tapped
    await shot('focus-newbest');
    const w = await driver.getWindowSize();
    await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
      { type: 'pointerMove', duration: 0, x: Math.round(w.width / 2), y: Math.round(w.height / 2) },
      { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 60 }, { type: 'pointerUp', button: 0 } ] }]);
    await driver.releaseActions(); await sleep(900);
  }
  await id('focus.skip').waitForExist({ timeout: 6000 });                // check re-lays the same screen out as rest
  await sleep(400); await shot('focus-rest');
  await id('session.focus').click(); await sleep(700);                   // one clock: the table's chip is counting the same rest
  const chip = await id('rest.chip').getAttribute('label').catch(() => '?');
  await id('session.focus').click(); await sleep(700);
  await id('focus.skip').waitForExist({ timeout: 4000 });                // and focus comes back still resting
  await id('focus.skip').click(); await sleep(700);
  await id('focus.check').waitForExist({ timeout: 4000 });
  await id('session.focus').click(); await sleep(700);
  await id('slide.finish').waitForExist({ timeout: 6000 });
  if (!/\d:\d\d/.test(chip)) throw new Error(`check did not arm the shared rest clock: ${chip}`);
  return `check → rest ${chip} → skip → set`;
});
await step('session-scroll', async () => {
  // drag in the left gutter (row numbers, non-interactive) — mid-screen hits kg/reps fields which eat the pan
  const win = await driver.getWindowSize();
  const gutterScroll = async () => { const x = Math.round(win.width * 0.05);
    const steps = Array.from({ length: 6 }, (_, i) => ({ type: 'pointerMove', duration: 60, x, y: Math.round(win.height * 0.62 - (win.height * 0.47 / 6) * (i + 1)) }));
    await driver.performActions([{ type: 'pointer', id: 'f1', parameters: { pointerType: 'touch' }, actions: [
      { type: 'pointerMove', duration: 0, x, y: Math.round(win.height * 0.62) }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 80 },
      ...steps, { type: 'pointerUp', button: 0 } ] }]); await driver.releaseActions(); };
  let prevY = Infinity;                                  // scroll to the very end: swipe until the pill stops moving
  for (let i = 0; i < 8; i++) {
    await gutterScroll(); await sleep(450);
    const y = (await rect(id('+ Add exercise'))).y;
    if (Math.abs(y - prevY) < 4) break; prevY = y;
  }
  const add = await rect(id('+ Add exercise')); const slide = await rect(id('slide.finish'));
  await shot('session-bottom');
  if (add.y + add.h > slide.y) throw new Error(`add pill bottom ${Math.round(add.y + add.h)} under slider top ${Math.round(slide.y)}`);
  return `pill clears slider by ${Math.round(slide.y - add.y - add.h)}pt`;
});
await step('live-activity', async () => {
  await driver.execute('mobile: backgroundApp', { seconds: -1 }); await sleep(1500);
  await shot('dynamic-island');
  const src = await driver.getPageSource();
  const hits = [...src.matchAll(/(?:label|name|value)="([^"]*(?:%|LEGS|in progress)[^"]*)"/gi)].map(m => m[1]).slice(0, 4);
  await driver.execute('mobile: activateApp', { bundleId: 'com.vaibhavgautam.lightweight' });
  await id('set.check.0').waitForExist({ timeout: 8000 }); await sleep(300);
  if (!hits.length) throw new Error('no live-activity content in springboard source');
  return hits.join(' · ').slice(0, 90);
});
await step('lock-banner', async () => {
  await driver.lock(); await sleep(1800);
  const src = await driver.getPageSource();
  const next = [...src.matchAll(/(?:label|name|value)="((?:NEXT · |SET \d)[^"]+)"/g)].map(m => m[1]);
  await shot('lock-banner');
  await driver.unlock(); await sleep(800);
  await driver.execute('mobile: activateApp', { bundleId: 'com.vaibhavgautam.lightweight' });
  await id('set.check.0').waitForExist({ timeout: 8000 }); await sleep(300);
  if (!next.length) throw new Error('NEXT-set row not on lock banner');
  return next[0].slice(0, 70);
});
await step('minimize', async () => {
  await id('session.minimize').click(); await onScreen('home.resume', 8000); await sleep(400); await shot('home-live-card');
});
await step('pill-on-workouts', async () => {
  await swipeUntil('left', 'page.workouts');
  await onScreen('home.resume'); await sleep(300); await shot('home-live-card2');
});
await step('resume-from-pill', async () => {
  const ms = await go(id('home.resume'), id('slide.finish')); await sleep(300); return `${ms}ms`;
});
await step('slide-finish', async () => { const t = Date.now();
  await drag(id('slide.finish')); await sleep(600);                                    // unchecked sets -> pill ARMS
  const armedLabel = await id('slide.finish').getAttribute('label');
  if (!/again/i.test(armedLabel)) throw new Error(`pill did not arm: ${armedLabel}`);
  await shot('finish-armed');
  await drag(id('slide.finish'));                                                       // second slide within 3s finishes
  await id('summary.done').waitForExist({ timeout: 8000 }); await sleep(500); await shot('summary-new');
  await id('coach.ask').click(); await id('coach.rpe.1').waitForExist({ timeout: 4000 }); await id('coach.rpe.1').click();
  // --coach-fail-once: the first generation fails → error row must appear, tap retries, read lands
  const err = await id('coach.error').waitForExist({ timeout: 8000 }).catch(() => false);
  if (err) { await shot('coach-error'); await id('coach.error').click(); }
  await id('coach.read').waitForExist({ timeout: 12000 });
  if (!(await id('coach.read.body').isExisting())) { await id('coach.read').click(); await sleep(400); }
  await id('coach.read.change.0').waitForExist({ timeout: 3000 }); await id('coach.read.accept.0').waitForExist({ timeout: 2000 });
  await sleep(300); await shot('coach-read');
  const r = await rect(id('summary.done')); const win = await driver.getWindowSize();
  if (r.y + r.h > win.height - 16) throw new Error(`DONE CTA cut off: bottom ${Math.round(r.y + r.h)} vs ${win.height}`);
  const ms = await go(id('summary.done'), id('home.start')); await sleep(400); await shot('home-after');
  const nextAfter = await id('home.start').getAttribute('label');                       // MVP sanity: the loop must advance
  if (nextAfter === nextBefore) throw new Error(`loop did not advance: still "${nextAfter}"`);
  return `finish ${Date.now() - t}ms · done ${ms}ms · loop advanced`; });

await step('logo-longpress', async () => {
  for (let i = 0; i < 4; i++) {                      // steer to Home by where the hero actually is
    const el = await driver.$('~routine.hero');
    const { x } = await el.getLocation();
    if (x >= 0 && x < 200) break;
    await driver.execute('mobile: swipe', { direction: x > 0 ? 'left' : 'right' }); await sleep(600);
  }
  await onScreen('routine.hero');
  const logo = await onScreen('home.logo');
  const loc = await logo.getLocation(); const sz = await logo.getSize();
  const x = Math.round(loc.x + sz.width / 2), y = Math.round(loc.y + sz.height / 2);
  const hold = () => driver.performActions([{ type: 'pointer', id: 'lp', parameters: { pointerType: 'touch' }, actions: [
    { type: 'pointerMove', duration: 0, x, y }, { type: 'pointerDown', button: 0 },
    { type: 'pause', duration: 800 }, { type: 'pointerUp', button: 0 }] }]);
  const v0 = await logo.getAttribute('value');
  await hold(); await sleep(800);
  const v1 = await (await driver.$('~home.logo')).getAttribute('value');
  await shot('theme-flip');
  await hold(); await sleep(800);
  const v2 = await (await driver.$('~home.logo')).getAttribute('value');
  if (!/^(light|dark)$/.test(v1) || !/^(light|dark)$/.test(v2) || v1 === v2) throw new Error(`flip broken: ${v0} → ${v1} → ${v2}`);
  return `${v0} → ${v1} → ${v2}`;
});

await step('account-open', async () => {
  const ms = await go(await onScreen('home.logo'), id('account.signout'));   // the page mark is the account button
  await id('account.sessions').waitForExist({ timeout: 3000 });
  await id('account.streak').waitForExist({ timeout: 2000 });
  await id('account.import').waitForExist({ timeout: 2000 });
  await sleep(400); await shot('account');
  return `${ms}ms`;
});
await step('account-appearance', async () => {
  const on = async (m) => await id(`account.appearance.${m}`).getAttribute('selected');
  await id('account.appearance.light').click(); await sleep(600);
  if ((await on('light')) !== 'true') throw new Error(`light not selected (${await on('light')})`);
  await shot('account-light');
  await id('account.appearance.dark').click(); await sleep(600);             // leave the board dark for later shots
  if ((await on('dark')) !== 'true') throw new Error('dark not restored');
  return 'light → dark applies immediately';
});
await step('account-back', async () => { const ms = await go(id('account.back'), id('home.start')); return `${ms}ms`; });
await step('sign-out-in', async () => {
  await go(await onScreen('home.logo'), id('account.signout'));
  await id('account.signout').click();
  const confirm = driver.$('-ios class chain:**/XCUIElementTypeAlert/**/XCUIElementTypeButton[`label == "Sign out"`]');
  await confirm.waitForExist({ timeout: 4000 }); await confirm.click();
  await id('login.apple').waitForExist({ timeout: 6000 }); await sleep(700); await shot('login');
  const ms = await go(id('login.apple'), id('home.start'), 12000);           // the stub flips the mock state after a beat
  return `${ms}ms`;
});
await step('login-offline', async () => {
  await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
  await new Promise(r => setTimeout(r, 800));
  await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: [...LAUNCH_ARGS, '--signed-out', '--auth-offline'] });
  await id('login.caption').waitForExist({ timeout: 10000 });
  await id('login.apple').click(); await sleep(1800);                        // fails the way a cancel does: no toast, button back
  const caption = await id('login.caption').getAttribute('label');
  await shot('login-offline');
  if (!/No connection/.test(caption || '')) throw new Error(`caption did not swap: ${caption}`);
  if (!(await id('login.apple').isEnabled())) throw new Error('apple button stayed disabled after failure');
  await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
  await new Promise(r => setTimeout(r, 800));
  await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: LAUNCH_ARGS });
  await onScreen('home.start', 12000);
  return caption;
});

await step('deeplink', async () => {
  await driver.execute('mobile: deepLink', { url: 'lightweight://calendar', bundleId: 'com.vaibhavgautam.lightweight' });
  await sleep(900);
  await onScreen('header.calendar');
  await driver.execute('mobile: deepLink', { url: 'lightweight://start', bundleId: 'com.vaibhavgautam.lightweight' });
  await sleep(900);
  await onScreen('routine.hero');
  return 'calendar + start land';
});

await step('empty-states', async () => {
  await driver.execute('mobile: terminateApp', { bundleId: 'com.vaibhavgautam.lightweight' }).catch(() => {});
  await new Promise(r => setTimeout(r, 800));
  await driver.execute('mobile: launchApp', { bundleId: 'com.vaibhavgautam.lightweight', arguments: ['--today', '2026-08-27', '--empty-demo'] });
  await sleep(2500);
  await id('empty.home').waitForExist({ timeout: 10000 }); await id('empty.home.loop').waitForExist({ timeout: 3000 }); await shot('empty-home');
  await driver.execute('mobile: swipe', { direction: 'left' }); await sleep(700);
  await id('empty.workouts.card').waitForExist({ timeout: 5000 }); await id('empty.workouts.slots').waitForExist({ timeout: 2000 }); await shot('empty-workouts');
  await driver.execute('mobile: swipe', { direction: 'left' }); await sleep(700);
  await id('empty.calendar').waitForExist({ timeout: 5000 }); await shot('empty-calendar');
  return '1a · 1b · 1c render';
});

console.log('\nRESULTS'); for (const [k, v, ms, info] of results) console.log(`  ${v === 'ok' ? '✓' : '✗'} ${k.padEnd(16)} ${String(ms).padStart(5)}ms  ${info || ''}`);
await driver.deleteSession();
process.exit(results.some(([, v]) => v !== 'ok') ? 1 : 0);   // red steps must fail the process — deploy gates depend on it
