// Both actual PHP entrypoints + real Chromium, isolated SQLite/JSON/session fixtures only.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),net=require('node:net');
const {spawn,execFileSync}=require('node:child_process');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const php=process.env.PHP_BINARY||'php',mySub=process.env.NIRA_TEST_MYSUB_ROOT||path.resolve(__dirname,'../../../../my-sub');
const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'nira-auth-browser-'));
const key=Buffer.alloc(32,7).toString('base64');
let server,browser,logs='';
const password='fixture-password-123';
function code(secret){return execFileSync(php,[path.join(__dirname,'auth_fixture_code.php'),secret],{windowsHide:true,encoding:'utf8'}).trim();}
async function form(page,action){return page.locator(`form:has(input[name="action"][value="${action}"])`).first();}
async function submit(page,action,values={}){await page.waitForLoadState('networkidle');const f=await form(page,action);for(const [name,value] of Object.entries(values)){if(name==="recovery_code")await f.locator("details").evaluate(e=>e.open=true);await f.locator(`[name="${name}"]`).fill(value);}await Promise.all([page.waitForNavigation({waitUntil:'domcontentloaded'}),f.locator('button[type=submit],button:not([type])').first().click()]);await page.waitForLoadState('networkidle');}
(async()=>{
 const listen=net.createServer();await new Promise(resolve=>listen.listen(0,'127.0.0.1',resolve));const port=listen.address().port;await new Promise(resolve=>listen.close(resolve));const base='http://127.0.0.1:'+port;
 server=spawn(php,['-S','127.0.0.1:'+port,path.join(__dirname,'auth_browser_router.php')],{env:{...process.env,NIRA_STORAGE_DIR:fixture,NIRA_SETUP_TOKEN:'fixture-host-token',NIRAN_ADMIN_SETUP_TOKEN:'fixture-host-token',NIRAN_REGISTRY_DB:path.join(fixture,'registry.sqlite'),NIRA_SUB_ADMIN_TOTP_KEY:key,NIRAN_ADMIN_TOTP_KEY:Buffer.alloc(32,9).toString('base64'),NIRA_TEST_MYSUB_ROOT:mySub},stdio:['ignore','pipe','pipe'],windowsHide:true});
 server.stdout.on('data',v=>logs+=v);server.stderr.on('data',v=>logs+=v);
 for(let i=0;i<80;i++){try{await fetch(base+'/admin/index.php');break;}catch(_){await new Promise(resolve=>setTimeout(resolve,50));}}
 browser=await chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
 for(const app of [{path:'/admin/index.php',username:'studio-admin',security:'/admin/security.php',api:true,cookie:'nira_subscription_trust'},{path:'/apiniraN/index.php',username:'registry-admin',security:'/apiniraN/index.php',api:false,cookie:'niran_registry_trust'}]){
   const context=await browser.newContext({viewport:{width:1280,height:1000}}),page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));
   await page.goto(base+app.path);
   await submit(page,'setup',{username:app.username,password,setup_token:'fixture-host-token',...(app.api?{}:{password_confirmation:password})});
   await page.goto(base+app.security);
   if(!app.api)await page.locator('details.card').first().evaluate(e=>e.open=true);
   await submit(page,'begin_2fa',{current_password:password});
   const manual=await page.locator('code.secret-value').innerText();assert.match(manual,/^[A-Z2-7]+$/);
   assert.equal(await page.locator('img[alt="Local authenticator setup QR"]').count(),1);
   if(process.env.NIRA_QR_PYTHON){const image=path.join(fixture,app.username+'-qr.png');await page.locator('img[alt="Local authenticator setup QR"]').screenshot({path:image});execFileSync(process.env.NIRA_QR_PYTHON,[path.join(__dirname,'qr_decode_test.py'),image,manual],{windowsHide:true,stdio:'pipe'});}
   const otp=await form(page,'confirm_2fa');const input=otp.locator('[name=code]');assert.equal(await input.getAttribute('maxlength'),'6');assert.equal(await input.getAttribute('autocomplete'),'one-time-code');
   // Native single-field editing: paste, replacement and Backspace retain normal browser behavior.
   await input.fill('123456');await input.press('Backspace');assert.equal(await input.inputValue(),'12345');
   const before=await context.cookies();await submit(page,'confirm_2fa',{code:code(manual)});
   const recovery=(await page.locator('pre.secret-value').innerText()).trim().split(/\s+/);assert.equal(recovery.length,10);
   assert.notEqual((await context.cookies()).find(c=>c.name.includes('admin'))?.value,before.find(c=>c.name.includes('admin'))?.value,'2FA confirmation regenerates session');
   await page.goto(base+app.path);await submit(page,'logout');
   const prePassword=await context.cookies();
   await submit(page,'login',{username:app.username,password});
   assert.equal(await page.locator('form:has(input[value="verify_2fa"])').count(),1,'OTP stage visible');
   if(app.api){const status=await page.evaluate(async()=> (await fetch('api.php')).status);assert.equal(status,401,'pending session cannot list subscriptions');}
   assert.notEqual((await context.cookies()).find(c=>c.name.includes('admin'))?.value,prePassword.find(c=>c.name.includes('admin'))?.value,'password stage regenerates session');
   const verify=await form(page,'verify_2fa');await verify.locator('[name=remember]').check();await submit(page,'verify_2fa',{recovery_code:recovery[0]});
   const trusted=(await context.cookies()).find(c=>c.name===app.cookie);assert.ok(trusted?.secure&&trusted.httpOnly&&trusted.sameSite==='Lax',JSON.stringify({url:page.url(),cookieNames:(await context.cookies()).map(c=>c.name),alerts:await page.locator('[role=alert],.notice.error').allTextContents(),otp:await page.locator('form:has(input[value=verify_2fa])').count()}));assert.ok(trusted.expires>Date.now()/1000+14.9*86400&&trusted.expires<Date.now()/1000+15.1*86400);
   await submit(page,'logout');await page.goto(base+app.path);assert.equal(await page.locator('form:has(input[value="login"])').count(),1,'remember is not autologin');
   await submit(page,'login',{username:app.username,password});assert.equal(await page.locator('form:has(input[value="verify_2fa"])').count(),0,'remember skips 2FA after correct password');
   const rotated=(await context.cookies()).find(c=>c.name===app.cookie);assert.notEqual(rotated.value,trusted.value,'remember rotates');assert.ok(Math.abs(rotated.expires-trusted.expires)<2,'rotation preserves original deadline (browser clock correction <2s)');
   await page.goto(base+app.security);if(!app.api)await page.locator('details.card').first().evaluate(e=>e.open=true);
   await submit(page,'change_username',{username:app.username+'2',current_password:password,recovery_code:recovery[1]});
   assert.equal((await context.cookies()).filter(c=>c.name===app.cookie).length,0,'identity change clears remember cookie');
   await page.goto(base+app.path);await submit(page,'logout');await submit(page,'login',{username:app.username+'2',password});
   await submit(page,'verify_2fa',{recovery_code:recovery[0]});assert.equal(await page.locator('form:has(input[value="verify_2fa"])').count(),1,'used recovery denied: '+JSON.stringify({url:page.url(),alerts:await page.locator('[role=alert],.notice.error').allTextContents()}));
   await submit(page,'verify_2fa',{recovery_code:recovery[2]});
   await page.goto(base+app.security);if(!app.api)await page.locator('details.card').first().evaluate(e=>e.open=true);
   await submit(page,'disable_2fa',{current_password:password,recovery_code:recovery[3]});
   await page.goto(base+app.path);await submit(page,'logout');await submit(page,'login',{username:app.username+'2',password});assert.equal(await page.locator('form:has(input[value="verify_2fa"])').count(),0,'disabled OTP no longer challenged');
   for(const viewport of [{width:1280,height:1000},{width:390,height:844}]){await page.setViewportSize(viewport);await page.goto(base+app.security);if(!app.api)await page.locator('details.card').first().evaluate(e=>e.open=true);assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'security view fits viewport');}
   assert.deepEqual(errors,[],'no browser exceptions');await context.close();console.log('PASS browser auth flow '+app.username);
 }
 console.log('Both panels: real browser auth/2FA/recovery/remember/revocation and mobile layout passed');
})().catch(e=>{console.error(e);if(/Fatal error|Warning:/.test(logs))console.error(logs);process.exitCode=1;}).finally(async()=>{if(browser)await browser.close();if(server){server.kill();await new Promise(resolve=>server.once('exit',resolve));}fs.rmSync(fixture,{recursive:true,force:true});});
