## فارسی
نسخهٔ **۱.۲.۴** — تغییرات نسبت به ۱.۲.۳:

- پشتیبانی از JSON کامل **Xray و sing-box** در کنار لینک‌های معمولی اشتراک؛ حفظ DNS و مسیریابی خود JSON.
- بخش جداگانهٔ **Aether** با پروفایل شخصی MASQUE، وارپ/WireGuard و WireGuard روی MASQUE، زنجیرهٔ اختیاری **سایفون**، انتخاب کشور، تنظیمات ساده/پیشرفته، اسکن و بررسی دستی IP و تعویض امن کلید.
- پینگ واقعی JSON و اتر با معیار هماهنگِ کمترین زمان دو درخواست؛ ثبت مصرف امروز/ماه JSON کامل Xray بدون دوباره‌شماری خروجی‌های زنجیره‌ای.
- اصلاح قطع و راه‌اندازی مجدد، لغو اتصالِ در حال انجام و تداخل VPN دیگر؛ ذخیرهٔ تنظیمات اتر فعال، همان اتصال را ری‌استارت می‌کند.
- بهبود نوارهای سرور و اتر، تعداد کنار عنوان، بازشدن سبک‌تر، ترتیب و پرچم‌ها؛ اصلاح اسکرول کشورها، جای Save، تنظیمات پیشرفته و آیکن سایفون. حفظ طراحی Glass/Clay و اصلاح پس‌زمینهٔ دارک و پنجرهٔ دانلود Performance Mode.

بهتر است کاربران نسخه‌های قبلی **روی همان برنامه آپدیت کنند**؛ حذف یا پاک‌کردن داده لازم نیست. هستهٔ Xray قبلی حفظ شده و بررسی TLS خاموش نشده است. مصرف ثبت‌نشدهٔ گذشته قابل بازسازی نیست و پینگ اتر در آماده‌سازی اولیه ممکن است بیشتر طول بکشد.

## English
**1.2.4** — changes since 1.2.3:

- Full **Xray and sing-box JSON** alongside ordinary subscription links, retaining each JSON's own DNS and routing.
- Separate personal **Aether** profiles: MASQUE, WARP/WireGuard and WireGuard over MASQUE, optional **Psiphon**, region selection, simple/advanced controls, IP discovery/manual checks and safe identity renewal.
- Real JSON/Aether HTTPS latency probes with the same best-of-two criterion, plus daily/monthly full-Xray JSON traffic accounting without counting chained outbounds twice.
- Improved VPN takeover, disconnect, cancellation and restart handling. Saving changed settings of the active Aether profile restarts that connection.
- Refined server/Aether groups, counts beside titles, lighter expansion, ordering and country indicators; fixed region-list scrolling, Save placement, advanced settings and Psiphon artwork. Glass/Clay remains, with dark-background and Performance Mode download-dialog fixes.

**Updating existing installations is recommended.** Install over the signed app without clearing data. The previous Xray core is retained and TLS verification remains enabled. Historical traffic gaps cannot be reconstructed; cold Aether preparation can take longer than ordinary probes.

### Downloads / دانلود
Android **7+ / API 24+**; **Aether requires Android 10+**. Version **1.2.4**, installation code **4058**.

| APK | Device / دستگاه |
| --- | --- |
| **arm64-v8a (v8)** | Most modern ARM phones / بیشتر گوشی‌های جدید |
| **armeabi-v7a (v7)** | 32-bit ARM / اندروید ARM سی‌ودوبیتی |
| **x86_64** | Compatible x86-64 devices and emulators |
| **Universal** | All three ABIs; choose if unsure / اگر مطمئن نیستید |

`SHA256SUMS.txt` contains file checksums. The x86_64 Psiphon runtime currently uses 4 KiB ELF alignment; its use on 16 KiB-page systems is not supported. Region availability, fixed exit IPs and 120 FPS are not guaranteed. Companion my-sub server changes require separate deployment; publishing this Android release does not deploy a host update.

[Detailed bilingual changes](https://github.com/bardia-us/niraNG/blob/v1.2.4/assets/release_notes/1.2.4.md)
