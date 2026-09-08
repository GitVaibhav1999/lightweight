import { remote } from 'webdriverio';
const UDID='51D5EF9F-B33D-43D1-BB51-7C7E5856AF80';
const ARGS=['--today','2025-09-10','--mock-auth'];
const d=await remote({hostname:'127.0.0.1',port:4723,path:'/',logLevel:'error',capabilities:{
 platformName:'iOS','appium:automationName':'XCUITest','appium:udid':UDID,
 'appium:bundleId':'com.vaibhavgautam.lightweight','appium:noReset':true,
 'appium:processArguments':{args:ARGS},'appium:newCommandTimeout':300,
 'appium:wdaLaunchTimeout':300000,'appium:waitForQuiescence':false}});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
await d.execute('mobile: terminateApp',{bundleId:'com.vaibhavgautam.lightweight'}).catch(()=>{});
await sleep(800);
await d.execute('mobile: launchApp',{bundleId:'com.vaibhavgautam.lightweight',arguments:ARGS});
await sleep(5000);
const t0=Date.now();
await d.$('~nav.tab.calendar').click();
await d.$('~year.strip').waitForExist({timeout:20000});
console.log(`calendar + year strip visible: ${Date.now()-t0}ms`);
await sleep(600); await d.saveScreenshot('./verify/cal-strip.png');
for (let i=0;i<5;i++){ const t=Date.now(); await d.execute('mobile: swipe',{direction:'up'}); await sleep(300); console.log(`  swipe ${i+1}: ${Date.now()-t}ms`); }
const s=await d.getPageSource();
console.log('history:', (s.match(/All history · (\d+) sessions/)||['(not reached)'])[0]);
console.log('sentinel:', (s.match(/(\d+) older/)||['none'])[0]);
await d.saveScreenshot('./verify/cal-history.png');
await d.deleteSession();
