## English

### Changes
- Device Registry status now follows the Android display-version policy independently from Forced Update build numbers.
- The management panel marks devices that satisfy the current display-version policy as **Latest version**.

### Bug fixes
- Fixed the Forced In-app Update UI crash that occurred when an outdated build opened the update flow.
- Fixed active APK download progress occasionally moving backwards when a stale polling result arrived after a newer progress event.
- Fixed nested scrolling in What's New; the dialog now has one continuous scroll area while preserving formatted headings, bold text, lists, and spacing.
- Kept Download, Verify, and Install states deterministic during mandatory and optional updates.

## فارسی

### تغییرات
- وضعیت دستگاه در Device Registry حالا مستقل از شمارهٔ build آپدیت اجباری و فقط بر اساس policy نسخهٔ نمایشی اندروید محاسبه می‌شود.
- پنل مدیریت دستگاه‌هایی را که policy نسخهٔ نمایشی فعلی را دارند با نشان **Latest version** مشخص می‌کند.

### باگ‌های رفع‌شده
- کرش رابط کاربری Forced In-app Update هنگام بازکردن مسیر آپدیت از یک build قدیمی رفع شد.
- عقب‌رفتن گاه‌به‌گاه مقدار دانلود APK بر اثر رسیدن polling قدیمی پس از progress جدید رفع شد.
- اسکرول تو‌در‌توی What's New حذف شد؛ کل محتوا یک اسکرول پیوسته دارد و heading، متن ضخیم، فهرست و فاصله‌گذاری Markdown درست باقی مانده‌اند.
- وضعیت‌های Download، Verify و Install در آپدیت اجباری و عادی پایدار و قطعی شدند.
