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
await sleep(8000);
for (let i=0;i<14;i++){
  const t=Date.now();
  await d.execute('mobile: swipe',{direction:'up'});
  await sleep(280);
  const ms=Date.now()-t;
  if (i%4===0 || ms>900) console.log(`  swipe ${String(i+1).padStart(2)}: ${ms}ms`);
  const s=await d.getPageSource();
  if (/history\.more/.test(s)) {
    console.log(`  load-more reached after ${i+1} swipes: ${(s.match(/Show \d+ more/)||[''])[0]} · ${(s.match(/\d+ older/)||[''])[0]}`);
    const before=[...s.matchAll(/name="history\.row"/g)].length;
    await d.$('~history.more').click(); await sleep(900);
    const after=[...(await d.getPageSource()).matchAll(/name="history\.row"/g)].length;
    console.log(`  tapped: rendered rows ${before} -> ${after}`);
    break;
  }
}
await d.deleteSession();
