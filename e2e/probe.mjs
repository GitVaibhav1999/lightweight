import { remote } from 'webdriverio';
const UDID='51D5EF9F-B33D-43D1-BB51-7C7E5856AF80';
const ARGS=['--today','2025-09-10','--mock-auth','--screen','s8'];
const d=await remote({hostname:'127.0.0.1',port:4723,path:'/',logLevel:'error',capabilities:{
 platformName:'iOS','appium:automationName':'XCUITest','appium:udid':UDID,
 'appium:bundleId':'com.vaibhavgautam.lightweight','appium:noReset':true,
 'appium:processArguments':{args:ARGS},'appium:newCommandTimeout':300,
 'appium:wdaLaunchTimeout':300000,'appium:waitForQuiescence':false}});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
await d.execute('mobile: terminateApp',{bundleId:'com.vaibhavgautam.lightweight'}).catch(()=>{});
await sleep(900);
await d.execute('mobile: launchApp',{bundleId:'com.vaibhavgautam.lightweight',arguments:ARGS});
await sleep(9000);
const s = await d.getPageSource();
console.log('  page source length:', s.length);
console.log('  history.row count :', [...s.matchAll(/name="history\.row"/g)].length);
console.log('  history.more      :', /history\.more/.test(s) ? 'present' : 'ABSENT');
console.log('  "Show 50 more"    :', /Show \d+ more/.test(s) ? 'present' : 'absent');
console.log('  truncated?        :', s.trimEnd().endsWith('</AppiumAUT>') ? 'no' : 'YES — tree cut off');
await d.deleteSession();
