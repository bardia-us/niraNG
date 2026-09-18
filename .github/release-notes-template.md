## English

### Changes
- Device Registry status now follows the Android display-version policy independently from Forced Update build numbers.
- The management panel marks devices that satisfy the current display-version policy as **Latest version**.

### Bug fixes
- Fixed the Forced In-app Update UI crash that occurred when an outdated build opened the update flow.
- Fixed active APK download progress occasionally moving backwards when a stale polling result arrived after a newer progress event.
- Fixed nested scrolling in What's New; the dialog now has one continuous scroll area while preserving formatted headings, bold text, lists, and spacing.
- Kept Download, Verify, and Install states deterministic during mandatory and optional updates.
- Mandatory **Update now** now starts the verified in-app download immediately instead of opening a second browser/in-app choice.
- Mandatory download progress can no longer be hidden or dismissed accidentally; reopening the app rechecks the server policy, and Retry unlocks immediately when the minimum build is lowered.
- Fixed Markdown headings and paragraphs capturing independent hold/drag gestures inside What's New.
- Fixed the Device Registry marking every allowed version as **Latest version**; the badge now matches the actual latest GitHub Release independently from the minimum-version policy.

## فارسی

### تغییرات
- وضعیت دستگاه در Device Registry حالا مستقل از شمارهٔ build آپدیت اجباری و فقط بر اساس policy نسخهٔ نمایشی اندروید محاسبه می‌شود.
- پنل مدیریت دستگاه‌هایی را که policy نسخهٔ نمایشی فعلی را دارند با نشان **Latest version** مشخص می‌کند.

### باگ‌های رفع‌شده
- کرش رابط کاربری Forced In-app Update هنگام بازکردن مسیر آپدیت از یک build قدیمی رفع شد.
- عقب‌رفتن گاه‌به‌گاه مقدار دانلود APK بر اثر رسیدن polling قدیمی پس از progress جدید رفع شد.
- اسکرول تو‌در‌توی What's New حذف شد؛ کل محتوا یک اسکرول پیوسته دارد و heading، متن ضخیم، فهرست و فاصله‌گذاری Markdown درست باقی مانده‌اند.
- وضعیت‌های Download، Verify و Install در آپدیت اجباری و عادی پایدار و قطعی شدند.
- دکمهٔ **Update now** در آپدیت اجباری حالا بدون نمایش دوبارهٔ انتخاب مرورگر/داخل برنامه، مستقیماً دانلود امن داخل برنامه را آغاز می‌کند.
- پنجرهٔ پیشرفت آپدیت اجباری دیگر با Hide، لمس بیرون یا Back ناخواسته بسته نمی‌شود؛ با بازکردن دوبارهٔ برنامه policy سرور مجدداً بررسی می‌شود و Retry پس از پایین‌آوردن minimum فوراً قفل را باز می‌کند.
- گرفتن و کشیدن روی headingها و پاراگراف‌های Markdown دیگر اسکرول مستقل داخل پنجرهٔ What's New ایجاد نمی‌کند.
- باگ نمایش **Latest version** برای تمام نسخه‌های مجاز رفع شد؛ این نشان حالا مستقل از minimum policy دقیقاً با آخرین GitHub Release مطابقت داده می‌شود.
