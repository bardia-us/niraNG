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
باید از `android/local.properties`، Gradle properties یا Environment variables
در زمان Build تزریق شوند:

```properties
NIRANG_SUBSCRIPTION_URL=https://example.com/private-subscription
NIRANG_TELEGRAM_URL=https://t.me/private-invite
NIRANG_TELEGRAM_CONTACT=@contact
```

این مقادیر داخل APK نهایی وجود خواهند داشت؛ کلاینت موبایل نمی‌تواند در برابر
Reverse engineering محرمانگی کامل ایجاد کند.

## امضای Release

فایل‌های `android/key.properties` و `android/keystore/*.jks` عمداً توسط Git
نادیده گرفته می‌شوند. برای Build قابل به‌روزرسانی باید یک keystore ثابت و امن
نگه دارید؛ از دست رفتن آن مانع نصب نسخه‌های بعدی به‌عنوان Update می‌شود.

## Build و تست

```powershell
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

خروجی‌ها در مسیر زیر ساخته می‌شوند:

```text
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
```

## Native core

پروژه از `AndroidLibXrayLite v26.5.19` استفاده می‌کند. کتابخانه فعلی برای
`arm64-v8a`، `armeabi-v7a` و `x86_64` موجود است. مجوزهای اجزای ثالث در
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) ثبت شده‌اند.

## نکته Google Play Protect

APKهای Release با کلید اختصاصی niraNG امضا می‌شوند. با این حال APKهای
Sideload شده ممکن است تا زمانی که Developer/Package در Google Play سابقه و
اعتبار کافی پیدا کند هشدار Play Protect نمایش دهند. امضا برای Update امن ضروری
است، اما به‌تنهایی تضمین حذف هشدار Play Protect نیست.
