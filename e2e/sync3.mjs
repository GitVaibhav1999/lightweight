import { remote } from 'webdriverio';
const d=await remote({hostname:'127.0.0.1',port:4723,path:'/',logLevel:'error',capabilities:{
 platformName:'iOS','appium:automationName':'XCUITest','appium:udid':'51D5EF9F-B33D-43D1-BB51-7C7E5856AF80',
 'appium:bundleId':'com.vaibhavgautam.lightweight','appium:noReset':true,
 'appium:newCommandTimeout':300,'appium:wdaLaunchTimeout':300000,'appium:waitForQuiescence':false}});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
await d.execute('mobile: terminateApp',{bundleId:'com.vaibhavgautam.lightweight'}).catch(()=>{});
await sleep(800);
await d.execute('mobile: launchApp',{bundleId:'com.vaibhavgautam.lightweight',
  arguments:['--today','2025-09-10','--dev-signin','dev@lightweight.local','devpassword123']});
await sleep(9000);
await d.$('~nav.tab.workouts').click(); await sleep(1800);
const r = d.$('-ios predicate string:label CONTAINS[c] "New workout"');
if (await r.isExisting()) { await r.click(); await sleep(2000); }
const empty = d.$('~empty.workouts.slots');
if (await empty.isExisting()) { await empty.click(); await sleep(2500); console.log('opened the exercise picker'); }
const btns = await d.$$('XCUIElementTypeButton');
console.log('  buttons in picker:', btns.length);
for (const b of btns.slice(0, 30)) {
  const l = await b.getAttribute('label').catch(()=>'');
  if (l && /press|squat|curl|row|raise|fly|pulldown/i.test(l)) { await b.click(); console.log('  picked:', l.slice(0,40)); break; }
}
await sleep(3000);
await d.saveScreenshot('./verify/sync-3.png');
await d.deleteSession();
