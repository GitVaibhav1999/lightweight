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
const rows = async () => [...(await d.getPageSource()).matchAll(/name="history\.row"/g)].length;
console.log(`history rows rendered on arrival: ${await rows()}`);
const s = await d.getPageSource();
console.log('header:', (s.match(/all history · (\d+) sessions/i)||['(not on screen)'])[0]);
console.log('sentinel:', (s.match(/(\d+) older/)||['none'])[0]);
await d.saveScreenshot('./verify/count.png');
await d.deleteSession();
