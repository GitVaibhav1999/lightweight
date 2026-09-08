import { remote } from 'webdriverio';
const UDID = '51D5EF9F-B33D-43D1-BB51-7C7E5856AF80';
const ARGS = ['--today','2025-09-10','--dev-signin','dev@lightweight.local','devpassword123','--screen','s9'];
const d = await remote({ hostname:'127.0.0.1', port:4723, path:'/', logLevel:'error', capabilities:{
  platformName:'iOS','appium:automationName':'XCUITest','appium:udid':UDID,
  'appium:bundleId':'com.vaibhavgautam.lightweight','appium:noReset':true,
  'appium:processArguments':{args:ARGS},'appium:newCommandTimeout':600,
  'appium:wdaLaunchTimeout':300000,'appium:waitForQuiescence':false }});
const sleep = ms => new Promise(r=>setTimeout(r,ms));
await d.execute('mobile: terminateApp',{bundleId:'com.vaibhavgautam.lightweight'}).catch(()=>{});
await sleep(800);
await d.execute('mobile: launchApp',{bundleId:'com.vaibhavgautam.lightweight',arguments:ARGS});
await sleep(9000);
const row = d.$('~account.sync');
await row.waitForExist({timeout:15000});
await row.click();
console.log('tapped Push to Postgres');
for (let i=0;i<40;i++){
  await sleep(3000);
  const s = await d.getPageSource();
  const m = s.match(/(\d+ workouts · [^"]*?s)"/) || s.match(/name="([^"]*sessions · [^"]*)"/);
  if (m) { console.log('result:', m[1]); break; }
  if (/Sign in before syncing/.test(s)) { console.log('result: NOT SIGNED IN'); break; }
  if (i%4===3) console.log(`  …${(i+1)*3}s`);
}
await d.saveScreenshot('./verify/push.png');
await d.deleteSession();
