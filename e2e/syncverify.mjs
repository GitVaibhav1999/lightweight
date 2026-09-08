import { remote } from 'webdriverio';
const d=await remote({hostname:'127.0.0.1',port:4723,path:'/',logLevel:'error',capabilities:{
 platformName:'iOS','appium:automationName':'XCUITest','appium:udid':'51D5EF9F-B33D-43D1-BB51-7C7E5856AF80',
 'appium:bundleId':'com.vaibhavgautam.lightweight','appium:noReset':true,
 'appium:newCommandTimeout':300,'appium:wdaLaunchTimeout':300000,'appium:waitForQuiescence':false}});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const tap = async (sel, t=12000) => { const e=d.$(`~${sel}`); await e.waitForExist({timeout:t}); await e.click(); };
await d.execute('mobile: terminateApp',{bundleId:'com.vaibhavgautam.lightweight'}).catch(()=>{});
await sleep(800);
await d.execute('mobile: launchApp',{bundleId:'com.vaibhavgautam.lightweight',
  arguments:['--today','2025-09-10','--dev-signin','dev@lightweight.local','devpassword123']});
await sleep(9000);

// 1. create a workout
await tap('nav.tab.workouts'); await sleep(1500);
const src = await d.getPageSource();
if (/New workout/.test(src)) console.log('  (a workout already exists)');
const newBtn = d.$('-ios predicate string:label CONTAINS "New workout"');
if (await newBtn.isExisting()) { await newBtn.click(); console.log('STEP 1: created a workout'); await sleep(2500); }
await d.saveScreenshot('./verify/sync-1.png');
await d.deleteSession();
