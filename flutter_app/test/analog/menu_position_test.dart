import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watchparty/analog/chrome/analog_select.dart';
import 'package:watchparty/analog/player/analog_settings_stack.dart';
import 'package:watchparty/ui/ui.dart';

/// Stands in for the player's bottom chrome: a scrubber with a control row
/// underneath it, pinned to the bottom of the stage.
class _Bar extends StatelessWidget {
  const _Bar({required this.timelineKey, required this.trailing});

  final GlobalKey timelineKey;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomCenter,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(key: timelineKey, height: 24, color: Colors.white24),
        Row(children: [const Spacer(), trailing]),
      ],
    ),
  );
}

void main() {
  testWidgets('settings panel clears the timeline', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final timeline = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: _Bar(
            timelineKey: timeline,
            trailing: AnalogSettingsStack(
              liftAbove: timeline,
              entries: [
                AnalogSettingsEntry(
                  icon: Icons.hd_outlined,
                  label: 'Quality',
                  detail: 'Auto',
                  onTap: () {},
                ),
                AnalogSettingsEntry(
                  icon: Icons.speed_outlined,
                  label: 'Speed',
                  detail: '1x',
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();

    // The gear sits in the row BELOW the scrubber, so a panel that merely
    // opened "upward from the gear" would land on top of the bar.
    final timelineTop = tester.getRect(find.byKey(timeline)).top;
    expect(tester.getRect(find.text('Quality')).bottom, lessThan(timelineTop));
    expect(tester.getRect(find.text('Speed')).bottom, lessThan(timelineTop));
  });

  testWidgets('track picker clears the timeline', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final timeline = GlobalKey();
    final anchor = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: _Bar(
            timelineKey: timeline,
            trailing: Builder(
              builder: (context) => IconButton(
                key: anchor,
                icon: const Icon(Icons.subtitles),
                onPressed: () => showAnalogSelect<String?>(
                  context: context,
                  anchor: anchor,
                  liftAbove: timeline,
                  selected: null,
                  groups: const [
                    AnalogChoiceGroup<String?>(
                      icon: Icons.subtitles,
                      choices: [
                        AnalogChoice<String?>(value: null, label: 'Off'),
                        AnalogChoice<String?>(value: 'a', label: 'English'),
                      ],
                    ),
                  ],
                  footerIcon: Icons.upload_file_outlined,
                  footerTooltip: 'Load subtitle file',
                  onFooter: () {},
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(anchor));
    await tester.pumpAndSettle();

    // The footer is the LAST row, so if it clears the bar the whole menu does.
    final timelineTop = tester.getRect(find.byKey(timeline)).top;
    expect(
      tester.getRect(find.text('Load subtitle file')).bottom,
      lessThan(timelineTop),
    );
  });
}
