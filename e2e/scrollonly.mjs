import { remote } from 'webdriverio';
const d=await remote({hostname:'127.0.0.1',port:4723,path:'/',logLevel:'error',capabilities:{
 platformName:'iOS','appium:automationName':'XCUITest','appium:udid':'51D5EF9F-B33D-43D1-BB51-7C7E5856AF80',
 'appium:bundleId':'com.vaibhavgautam.lightweight','appium:noReset':true,
 'appium:newCommandTimeout':300,'appium:wdaLaunchTimeout':300000,'appium:waitForQuiescence':false}});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
for (let i=0;i<26;i++){ await d.execute('mobile: swipe',{direction: i%6<3?'up':'down'}); await sleep(120); }
await d.deleteSession();
