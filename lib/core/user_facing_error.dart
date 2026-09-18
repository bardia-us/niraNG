import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class UserFacingError {
  const UserFacingError({required this.title, required this.message});

  final String title;
  final String message;

  String get combined => '$title\n$message';
}

UserFacingError userFacingError(Object error, {required bool persian}) {
  final code = error is PlatformException ? error.code.toLowerCase() : '';
  if (error is TimeoutException ||
      error is SocketException && code == 'timeout' ||
      code == 'timeout') {
    return _localized(
      persian,
      'Request timed out',
      'Check your connection and try again. If the service is restricted, turn on a VPN and retry.',
      'زمان درخواست تمام شد',
      'اتصال اینترنت را بررسی و دوباره تلاش کنید. اگر دسترسی محدود است، VPN را روشن کنید و Retry بزنید.',
    );
  }
  if (error is SocketException ||
      {'network', 'host_unreachable', 'subscription_network'}.contains(code)) {
    return _localized(
      persian,
      'Network is unavailable',
      'Check the internet or try another network. If access to the server is restricted, turn on a VPN and retry.',
      'اتصال شبکه در دسترس نیست',
      'اینترنت را بررسی کنید یا با شبکه‌ای دیگر امتحان کنید. اگر سرور محدود است، VPN را روشن و دوباره تلاش کنید.',
    );
  }
  if (code == 'outdated') {
    return _localized(
      persian,
      'Update required',
      'This version is no longer supported. Install the latest official release to continue.',
      'آپدیت الزامی است',
      'این نسخه دیگر پشتیبانی نمی‌شود. برای ادامه آخرین نسخه رسمی را نصب کنید.',
    );
  }
  if (code == 'blocked') {
    return _localized(
      persian,
      'Access blocked',
      'This device has been blocked. Contact support if you think this is a mistake.',
      'دسترسی مسدود شده است',
      'دسترسی این دستگاه مسدود شده است. اگر فکر می‌کنید اشتباهی رخ داده با پشتیبانی تماس بگیرید.',
    );
  }
  if (code.contains('subscription') || error is FormatException) {
    return _localized(
      persian,
      'Subscription could not be loaded',
      'The link or server response is invalid. Check the subscription and try Update again.',
      'Subscription بارگذاری نشد',
      'لینک یا پاسخ سرور معتبر نیست. لینک را بررسی کنید و دوباره Update بزنید.',
    );
  }
  if (code.contains('registration') || code.contains('verification')) {
    return _localized(
      persian,
      'Device verification failed',
      'Check your connection and retry. Trying another network or enabling a VPN may help.',
      'تأیید دستگاه انجام نشد',
      'اتصال را بررسی و دوباره تلاش کنید. شبکه‌ای دیگر یا روشن‌کردن VPN ممکن است مشکل را حل کند.',
    );
  }
  if (code.contains('update')) {
    return _localized(
      persian,
      'Update failed',
      'The update service is temporarily unavailable. Check your connection and try again.',
      'آپدیت انجام نشد',
      'سرویس آپدیت موقتاً در دسترس نیست. اتصال را بررسی و دوباره تلاش کنید.',
    );
  }
  return _localized(
    persian,
    'Something went wrong',
    'Please try again. If the problem continues, restart the app or try another network.',
    'مشکلی پیش آمد',
    'دوباره تلاش کنید. اگر مشکل ادامه داشت، برنامه را باز کنید یا شبکه را تغییر دهید.',
  );
}

UserFacingError _localized(
  bool persian,
  String englishTitle,
  String englishMessage,
  String persianTitle,
  String persianMessage,
) => UserFacingError(
  title: persian ? persianTitle : englishTitle,
  message: persian ? persianMessage : englishMessage,
);
