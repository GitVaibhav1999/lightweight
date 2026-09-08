import { remote } from 'webdriverio';
const d=await remote({hostname:'127.0.0.1',port:4723,path:'/',logLevel:'error',capabilities:{
 platformName:'iOS','appium:automationName':'XCUITest','appium:udid':'51D5EF9F-B33D-43D1-BB51-7C7E5856AF80',
 'appium:bundleId':'com.vaibhavgautam.lightweight','appium:noReset':true,
 'appium:newCommandTimeout':300,'appium:wdaLaunchTimeout':300000,'appium:waitForQuiescence':false}});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const byLabel = s => d.$(`-ios predicate string:label CONTAINS[c] "${s}"`);
await d.execute('mobile: terminateApp',{bundleId:'com.vaibhavgautam.lightweight'}).catch(()=>{});
await sleep(800);
await d.execute('mobile: launchApp',{bundleId:'com.vaibhavgautam.lightweight',
  arguments:['--today','2025-09-10','--dev-signin','dev@lightweight.local','devpassword123']});
await sleep(9000);
await d.$('~nav.tab.workouts').click(); await sleep(1800);

// open the workout -> add an exercise (creates a slot)
const row = byLabel('New workout');
if (await row.isExisting()) { await row.click(); await sleep(1800); console.log('opened the workout'); }
const add = byLabel('Add exercise');
if (await add.isExisting()) {
  await add.click(); await sleep(2200);
  const first = d.$('-ios class chain:**/XCUIElementTypeButton[`label CONTAINS "Press"`][1]');
  if (await first.isExisting()) { await first.click(); console.log('STEP 2: added an exercise'); await sleep(2500); }
  else { const any = await d.$$('XCUIElementTypeButton'); if (any.length>6) { await any[6].click(); console.log('STEP 2: added an exercise (fallback)'); await sleep(2500); } }
}
await d.saveScreenshot('./verify/sync-2.png');
await d.deleteSession();
