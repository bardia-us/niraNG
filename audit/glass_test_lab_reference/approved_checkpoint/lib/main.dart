import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

void main() {
  runApp(const MyApp());
}

final ThemeData _lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF6750A4),
    brightness: Brightness.light,
  ),
);

final ThemeData _darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF8B7CFF),
    brightness: Brightness.dark,
  ),
);

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _dark = true;
  bool _liquidGlass = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _BouncyScrollBehavior(),
      themeAnimationDuration: Duration.zero,
      themeAnimationStyle: AnimationStyle.noAnimation,
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      home: TelegramStyleScreen(
        isDark: _dark,
        useLiquidGlass: _liquidGlass,
        onToggleTheme: () => setState(() => _dark = !_dark),
        onToggleGlass: () => setState(() => _liquidGlass = !_liquidGlass),
      ),
    );
  }
}

class _BouncyScrollBehavior extends MaterialScrollBehavior {
  const _BouncyScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

class _Conversation {
  const _Conversation(
    this.name,
    this.preview,
    this.time,
    this.color, {
    this.unread = false,
  });

  final String name;
  final String preview;
  final String time;
  final Color color;
  final bool unread;
}

const _conversations = <_Conversation>[
  _Conversation(
    'Nika Rahimi',
    'Can you send the photos from yesterday?',
    '4:42 PM',
    Colors.amber,
    unread: true,
  ),
  _Conversation(
    'Arman',
    'The new build feels much smoother now.',
    '4:18 PM',
    Colors.red,
  ),
  _Conversation(
    'Sara Mohammadi',
    'Voice Message · 0:42',
    '3:57 PM',
    Colors.blue,
    unread: true,
  ),
  _Conversation(
    'Kian',
    'Let’s meet around seven near the café.',
    '2:31 PM',
    Colors.green,
  ),
  _Conversation(
    'Mina & Leila',
    'Mina: That purple theme looks amazing ✨',
    '1:06 PM',
    Colors.purple,
  ),
  _Conversation('Daniel', 'Document.pdf · 2.4 MB', '12:48 PM', Colors.orange),
  _Conversation('Yasmin', 'Typing…', '11:20 AM', Colors.cyan, unread: true),
  _Conversation(
    'Reza Karimi',
    'I’ll call you when I arrive.',
    '10:05 AM',
    Colors.pink,
  ),
  _Conversation(
    'Noah Williams',
    'The download finished successfully.',
    'Yesterday',
    Colors.indigo,
  ),
  _Conversation('Leila', 'Pinned a message', 'Monday', Colors.teal),
];

class TelegramStyleScreen extends StatelessWidget {
  const TelegramStyleScreen({
    required this.isDark,
    required this.useLiquidGlass,
    required this.onToggleTheme,
    required this.onToggleGlass,
    super.key,
  });

  final bool isDark;
  final bool useLiquidGlass;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleGlass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFF2F2F7),
      body: SafeArea(
        child: BackdropGroup(
          child: Stack(
            children: [
              ListView.builder(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.only(top: 94, bottom: 100),
                itemCount: 34,
                itemBuilder: (context, index) {
                  final conversation =
                      _conversations[index % _conversations.length];
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(start: 14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 10,
                          child: conversation.unread
                              ? Container(
                                  width: 9,
                                  height: 9,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF0A84FF),
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: conversation.color,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            conversation.name.characters.first,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 78),
                            padding: const EdgeInsetsDirectional.only(
                              top: 11,
                              end: 15,
                              bottom: 10,
                            ),
                            decoration: BoxDecoration(
                              border: BorderDirectional(
                                bottom: BorderSide(
                                  color: scheme.outlineVariant.withValues(
                                    alpha: isDark ? .28 : .48,
                                  ),
                                  width: .55,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        conversation.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 17,
                                          height: 1.12,
                                          fontWeight: conversation.unread
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      conversation.time,
                                      style: TextStyle(
                                        color: conversation.unread
                                            ? const Color(0xFF0A84FF)
                                            : scheme.onSurfaceVariant,
                                        fontSize: 13.5,
                                        fontWeight: conversation.unread
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  conversation.preview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 15.5,
                                    height: 1.18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Positioned(
                top: 12,
                left: 14,
                right: 14,
                child: GlassContainer(
                  height: 72,
                  borderRadius: BorderRadius.circular(26),
                  useLiquidGlass: useLiquidGlass,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: useLiquidGlass
                              ? 'Liquid shader (B)'
                              : 'Frosted baseline (A)',
                          icon: Badge(
                            label: Text(useLiquidGlass ? 'B' : 'A'),
                            child: Icon(
                              useLiquidGlass
                                  ? Icons.water_drop_rounded
                                  : Icons.blur_on_rounded,
                            ),
                          ),
                          onPressed: onToggleGlass,
                        ),
                        const Expanded(
                          child: Text(
                            'Messages',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: isDark ? 'Light mode' : 'Dark mode',
                          icon: Icon(
                            isDark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                          ),
                          onPressed: onToggleTheme,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 12,
                left: 14,
                right: 14,
                child: GlassContainer(
                  height: 62,
                  borderRadius: BorderRadius.circular(31),
                  useLiquidGlass: useLiquidGlass,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_reaction_rounded,
                          color: scheme.onSurface.withValues(alpha: .74),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Message',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.attach_file_rounded,
                          color: scheme.onSurface.withValues(alpha: .74),
                        ),
                        const SizedBox(width: 10),
                        CircleAvatar(
                          radius: 21,
                          backgroundColor: scheme.primary,
                          child: Icon(
                            Icons.mic_rounded,
                            color: scheme.onPrimary,
                            size: 21,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// کامپوننت شیشه تمیز (Clean Frosted/Liquid Glass)
class GlassContainer extends StatelessWidget {
  static final ImageFilter _frostedBlur = ImageFilter.blur(
    sigmaX: 18.0,
    sigmaY: 18.0,
  );
  final Widget child;
  final double height;
  final BorderRadius borderRadius;
  final bool useLiquidGlass;

  const GlassContainer({
    super.key,
    required this.child,
    required this.height,
    required this.borderRadius,
    required this.useLiquidGlass,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (useLiquidGlass) {
      final radius = borderRadius.topLeft.x;
      return SizedBox(
        width: double.infinity,
        height: height,
        child: LiquidGlass.withOwnLayer(
          settings: LiquidGlassSettings(
            thickness: 17,
            blur: 9,
            refractiveIndex: 1.21,
            saturation: 1.25,
            chromaticAberration: .002,
            lightIntensity: dark ? .72 : .95,
            ambientStrength: dark ? .2 : .34,
            lightAngle: .7853981633974483,
            glassColor: dark
                ? Colors.white.withValues(alpha: .025)
                : Colors.black.withValues(alpha: .015),
          ),
          glassContainsChild: false,
          shape: LiquidRoundedRectangle(
            borderRadius: radius,
          ),
          child: SizedBox.expand(child: child),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: height,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter.grouped(
          filter: _frostedBlur,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark
                  ? Colors.white.withValues(alpha: .025)
                  : Colors.black.withValues(alpha: .015),
              borderRadius: borderRadius,
              border: Border.all(
                color: dark
                    ? Colors.white.withValues(alpha: .14)
                    : Colors.white.withValues(alpha: .56),
                width: 1.2,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
