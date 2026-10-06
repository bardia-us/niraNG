# niraNG

کلاینت اختصاصی و مینیمال Xray برای Android با Flutter، Kotlin و `VpnService`.

## امکانات

- ✅ اتصال واقعی VLESS، VMess و Trojan با Xray-core
- ✅ حالت VPN و Proxy-only
- ✅ پراکسی SOCKS محلی روی پورت پیش‌فرض `10808` در هر دو حالت
- ✅ تست تأخیر واقعی از مسیر Proxy با concurrency قابل تنظیم
- ✅ Subscription خصوصی، مصرف اشتراک و Auto Update
- ✅ Local DNS، FakeDNS، Remote DoH و Domain Strategy
- ✅ Routing ساده و معتبر: Global، Bypass LAN و Custom
- ✅ تعویض هوشمند Server بدون درخواست دوباره مجوز VPN
- ✅ Foreground notification با Action قطع اتصال
- ✅ رابط انگلیسی/فارسی، RTL/LTR و System/Light/Dark
- ✅ رابط شیشه‌ای سبک با Blur محدود و بدون Blur دائمی روی لیست‌ها
- ✅ حذف محلی Server و بازیابی Serverهای حذف‌شده
- ✅ نمایش اطلاعات فنی Server بدون Raw config یا Credentials

## امنیت Configها

niraNG عمداً قابلیت Import، Edit، Copy، Export یا Share کردن Raw config را
ارائه نمی‌کند. URL اشتراک و لینک خصوصی تلگرام داخل سورس عمومی قرار ندارند و
URL اشتراک دیگر داخل APK تزریق نمی‌شود. Subscription اصلی فقط در محیط backend
Device Registry با `NIRANG_SUBSCRIPTION_UPSTREAM` تنظیم می‌شود. اطلاعات تلگرام
همچنان در زمان Build از تنظیمات خصوصی تزریق می‌شوند:

```properties
NIRANG_TELEGRAM_URL=https://t.me/private-invite
NIRANG_TELEGRAM_CONTACT=@contact
```

مقادیر تلگرام داخل APK نهایی وجود خواهند داشت؛ کلاینت موبایل نمی‌تواند در برابر
Reverse engineering محرمانگی کامل آن‌ها را تضمین کند. راهنمای deployment و
migration رجیستری در `server/apiniraN/DEPLOYMENT.md` قرار دارد.

## امضای Release

فایل‌های `android/key.properties` و `android/keystore/*.jks` عمداً توسط Git
نادیده گرفته می‌شوند. برای Build قابل به‌روزرسانی باید یک keystore ثابت و امن
نگه دارید؛ از دست رفتن آن مانع نصب نسخه‌های بعدی به‌عنوان Update می‌شود.

## Build و تست

### انتخاب APK / Choosing an APK

- `arm64-v8a`: گوشی‌های ARM شصت‌وچهار‌بیتی؛ مناسب بیشتر گوشی‌های جدید.
- `armeabi-v7a`: دستگاه‌های ARM سی‌ودو‌بیتی.
- `x86_64`: دستگاه یا شبیه‌ساز x86 شصت‌وچهار‌بیتی؛ نسخهٔ همگانی نیست.
- `universal`: هر سه معماری در یک APK بزرگ‌تر؛ اگر معماری دستگاه را نمی‌دانید این فایل را بگیرید.

The universal APK contains ARM64, ARM32 and x86-64 native libraries. Android
selects the compatible library; it is not an x86 APK renamed as universal.
All builds require Android 7.0/API 24 or newer and a supported ABI.
Starting with 1.2.0, every output uses the same installation version code
(`4000 + base build`) so universal and split APKs can update each other.
The API/What's New base build number remains unchanged.

```powershell
flutter analyze
flutter test
flutter build apk --release --split-per-abi
# Build and name all four signed artifacts:
.\tool\build_release.ps1
```

خروجی‌ها در مسیر زیر ساخته می‌شوند:

```text
build/releases/v<version>/niraNG-v<version>-arm64-v8a.apk
build/releases/v<version>/niraNG-v<version>-armeabi-v7a.apk
build/releases/v<version>/niraNG-v<version>-x86_64.apk
build/releases/v<version>/niraNG-v<version>-universal.apk
```

## Native core

پروژه از `AndroidLibXrayLite v26.8.28` استفاده می‌کند. کتابخانه فعلی برای
`arm64-v8a`، `armeabi-v7a` و `x86_64` موجود است. مجوزهای اجزای ثالث در
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) ثبت شده‌اند.

## نکته Google Play Protect

APKهای Release با کلید اختصاصی niraNG امضا می‌شوند. با این حال APKهای
Sideload شده ممکن است تا زمانی که Developer/Package در Google Play سابقه و
اعتبار کافی پیدا کند هشدار Play Protect نمایش دهند. امضا برای Update امن ضروری
است، اما به‌تنهایی تضمین حذف هشدار Play Protect نیست.
