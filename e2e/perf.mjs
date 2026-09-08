import { remote } from 'webdriverio';
const UDID='51D5EF9F-B33D-43D1-BB51-7C7E5856AF80';
const ARGS=['--today','2025-09-10','--mock-auth','--screen','s8'];
const d=await remote({hostname:'127.0.0.1',port:4723,path:'/',logLevel:'error',capabilities:{
 platformName:'iOS','appium:automationName':'XCUITest','appium:udid':UDID,
 'appium:bundleId':'com.vaibhavgautam.lightweight','appium:noReset':true,
 'appium:processArguments':{args:ARGS},'appium:newCommandTimeout':300,
 'appium:wdaLaunchTimeout':300000,'appium:waitForQuiescence':false}});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const run = async (label) => {
  await d.execute('mobile: terminateApp',{bundleId:'com.vaibhavgautam.lightweight'}).catch(()=>{});
  await sleep(900);
  const t0=Date.now();
  await d.execute('mobile: launchApp',{bundleId:'com.vaibhavgautam.lightweight',arguments:ARGS});
  await d.$('~year.strip').waitForExist({timeout:30000});
  const launch=Date.now()-t0;
  await sleep(1500);
  const times=[];
  for (let i=0;i<10;i++){ const t=Date.now(); await d.execute('mobile: swipe',{direction:'up'}); times.push(Date.now()-t); }
  times.sort((a,b)=>a-b);
  console.log(`${label}  launch→strip ${launch}ms  swipe median ${times[5]}ms  max ${times[9]}ms  (no page-source in loop)`);
};
await run('calendar');
await d.deleteSession();
