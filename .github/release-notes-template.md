## English

### New features
- Added backend-controlled mandatory updates based on Android build number, with safe offline and timeout handling.
- Added a one-time “What’s New” dialog for each app version, using the matching bilingual GitHub release notes.
- Added the Servers action menu with service restart, result sorting, TCP delay, real delay, and subscription update actions.
- Added Mux controls, anti-spam controls, and an Advanced Settings action to reset all settings.

### Changes
- Refined the shared Liquid Glass experience across server chrome, menus, dialogs, and bottom sheets, with a simple opaque fallback in Performance Mode.
- Shifted the app’s light and dark palettes subtly toward niraNG purple while preserving contrast and readability.
- Improved subscription refresh behavior so temporary sorting and manual reordering are cleared when the subscription is replaced.
- Improved server editing and subscription parsing so configurations with different names are preserved deterministically.

### Bug fixes
- Replaced raw platform and network errors with localized, actionable messages for subscriptions, registration, device verification, and updates.
- Fixed the in-app updater appearing stuck at 100% while Android was verifying the downloaded APK; verification and install-ready states are now explicit and recover from missed native events.
- Fixed several Glass menu rendering, dismissal, animation, and first-frame issues.
- Fixed duplicate detection incorrectly removing otherwise distinct named configurations.
- Improved compatibility and validation for Android split APK releases.

## فارسی

### قابلیت‌های جدید
- آپدیت اجباری بر اساس شمارهٔ ساخت اندروید و قابل‌کنترل از سمت سرور اضافه شد؛ خطاهای موقت اینترنت و Timeout باعث قفل اشتباه برنامه نمی‌شوند.
- پنجرهٔ «چه چیزهایی جدید است؟» برای اولین اجرای هر نسخه اضافه شد و متن فارسی/انگلیسی را از Release همان نسخه در GitHub دریافت می‌کند.
- منوی عملیات صفحهٔ سرورها شامل راه‌اندازی مجدد سرویس، مرتب‌سازی نتایج، تست TCP، تست تأخیر واقعی و به‌روزرسانی اشتراک اضافه شد.
- تنظیمات Mux، کنترل ضداسپم و گزینهٔ بازنشانی کامل تنظیمات در بخش پیشرفته اضافه شد.

### تغییرات
- ظاهر Liquid Glass در سربرگ‌ها، منوها، دیالوگ‌ها و Bottom Sheetها یکدست‌تر شده و Performance Mode همچنان از سطح ساده و مات استفاده می‌کند.
- ته‌رنگ تم روشن و تیره کمی به بنفش niraNG نزدیک‌تر شده و خوانایی حفظ شده است.
- با به‌روزرسانی Subscription، مرتب‌سازی موقت و جابه‌جایی دستی قبلی پاک می‌شود و ترتیب اصلی اشتراک برمی‌گردد.
- پردازش Subscription و شناسه‌گذاری سرورها بهبود یافته تا کانفیگ‌هایی که نام متفاوت دارند به‌صورت قطعی حفظ شوند.

### باگ‌های رفع‌شده
- خطاهای خام PlatformException و متن‌های فنی شبکه در مسیر Subscription، ثبت دستگاه، اعتبارسنجی و Update با پیام‌های فارسی/انگلیسی قابل‌فهم و راهکار مناسب جایگزین شدند.
- گیر ظاهری دانلود آپدیت روی ۱۰۰٪ هنگام Verify شدن APK رفع شد؛ وضعیت بررسی فایل و آماده‌بودن نصب حالا جدا نمایش داده می‌شود و اگر رویداد نهایی Native از دست برود، وضعیت بازیابی می‌شود.
- چند مشکل مربوط به رندر، بسته‌شدن، انیمیشن و فریم اول منوهای Glass رفع شد.
- حذف اشتباه کانفیگ‌های هم‌اتصال ولی دارای نام متفاوت رفع شد.
- سازگاری و اعتبارسنجی APKهای تفکیک‌شدهٔ اندروید بهبود یافت.
