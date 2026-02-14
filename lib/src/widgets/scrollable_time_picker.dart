import 'package:flutter/material.dart';

/// Scrollable wheel-style time picker with AM/PM.
/// Uses ListWheelScrollView for smooth scrolling.
/// [primaryColor] controls accent color (defaults to blue).
Future<TimeOfDay?> showScrollableTimePicker(
  BuildContext context,
  TimeOfDay initialTime, {
  Color primaryColor = const Color(0xFF0066FF),
}) async {
  int selectedHour = initialTime.hourOfPeriod == 0 ? 12 : initialTime.hourOfPeriod;
  int selectedMinute = initialTime.minute;
  bool isAM = initialTime.period == DayPeriod.am;

  final hourController = FixedExtentScrollController(initialItem: selectedHour - 1);
  final minuteController = FixedExtentScrollController(initialItem: selectedMinute);
  final periodController = FixedExtentScrollController(initialItem: isAM ? 0 : 1);

  final result = await showModalBottomSheet<TimeOfDay>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: 380,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1E1E3F), Color(0xFF0D0D1A)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border.all(color: primaryColor.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 50,
                  height: 5,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      primaryColor.withValues(alpha: 0.3),
                      primaryColor,
                      primaryColor.withValues(alpha: 0.3),
                    ]),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(color: primaryColor.withValues(alpha: 0.5), blurRadius: 8),
                    ],
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.access_time_rounded, color: primaryColor, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'Seleccionar Hora',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                // Wheel pickers
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Selection indicator
                      Container(
                        width: 280,
                        height: 54,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: primaryColor.withValues(alpha: 0.6), width: 2),
                            bottom: BorderSide(color: primaryColor.withValues(alpha: 0.6), width: 2),
                          ),
                          gradient: LinearGradient(colors: [
                            primaryColor.withValues(alpha: 0.05),
                            primaryColor.withValues(alpha: 0.15),
                            primaryColor.withValues(alpha: 0.05),
                          ]),
                        ),
                      ),
                      // Wheels row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Hour wheel (1-12)
                          SizedBox(
                            width: 75,
                            child: ListWheelScrollView.useDelegate(
                              controller: hourController,
                              itemExtent: 54,
                              perspective: 0.003,
                              diameterRatio: 1.5,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (i) => setModalState(() => selectedHour = i + 1),
                              childDelegate: ListWheelChildBuilderDelegate(
                                childCount: 12,
                                builder: (_, i) {
                                  final hour = i + 1;
                                  final sel = hour == selectedHour;
                                  return Center(
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 150),
                                      style: TextStyle(
                                        fontSize: sel ? 36 : 24,
                                        fontWeight: sel ? FontWeight.bold : FontWeight.w400,
                                        color: sel ? Colors.white : Colors.white38,
                                        fontFamily: 'monospace',
                                      ),
                                      child: Text(hour.toString().padLeft(2, '0')),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          // Colon separator
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              ':',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: primaryColor,
                                shadows: [
                                  Shadow(color: primaryColor.withValues(alpha: 0.5), blurRadius: 10),
                                ],
                              ),
                            ),
                          ),
                          // Minute wheel (00-59)
                          SizedBox(
                            width: 75,
                            child: ListWheelScrollView.useDelegate(
                              controller: minuteController,
                              itemExtent: 54,
                              perspective: 0.003,
                              diameterRatio: 1.5,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (i) => setModalState(() => selectedMinute = i),
                              childDelegate: ListWheelChildBuilderDelegate(
                                childCount: 60,
                                builder: (_, i) {
                                  final sel = i == selectedMinute;
                                  return Center(
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 150),
                                      style: TextStyle(
                                        fontSize: sel ? 36 : 24,
                                        fontWeight: sel ? FontWeight.bold : FontWeight.w400,
                                        color: sel ? Colors.white : Colors.white38,
                                        fontFamily: 'monospace',
                                      ),
                                      child: Text(i.toString().padLeft(2, '0')),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // AM/PM wheel
                          SizedBox(
                            width: 70,
                            child: ListWheelScrollView.useDelegate(
                              controller: periodController,
                              itemExtent: 54,
                              perspective: 0.003,
                              diameterRatio: 1.5,
                              physics: const FixedExtentScrollPhysics(),
                              onSelectedItemChanged: (i) => setModalState(() => isAM = i == 0),
                              childDelegate: ListWheelChildBuilderDelegate(
                                childCount: 2,
                                builder: (_, i) {
                                  final period = i == 0 ? 'AM' : 'PM';
                                  final sel = (i == 0) == isAM;
                                  return Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: sel
                                          ? BoxDecoration(
                                              color: primaryColor.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: primaryColor.withValues(alpha: 0.5)),
                                            )
                                          : null,
                                      child: Text(
                                        period,
                                        style: TextStyle(
                                          fontSize: sel ? 22 : 18,
                                          fontWeight: sel ? FontWeight.bold : FontWeight.w400,
                                          color: sel ? primaryColor : Colors.white38,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Fade gradient top
                      Positioned(
                        top: 0, left: 0, right: 0, height: 50,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF1E1E3F), Color(0x001E1E3F)],
                            ),
                          ),
                        ),
                      ),
                      // Fade gradient bottom
                      Positioned(
                        bottom: 0, left: 0, right: 0, height: 50,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xFF0D0D1A), Color(0x000D0D1A)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: Colors.white24),
                            ),
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () {
                            int hour24;
                            if (isAM) {
                              hour24 = selectedHour == 12 ? 0 : selectedHour;
                            } else {
                              hour24 = selectedHour == 12 ? 12 : selectedHour + 12;
                            }
                            Navigator.pop(context, TimeOfDay(hour: hour24, minute: selectedMinute));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            shadowColor: primaryColor.withValues(alpha: 0.5),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_rounded, size: 20),
                              SizedBox(width: 8),
                              Text('CONFIRMAR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  hourController.dispose();
  minuteController.dispose();
  periodController.dispose();

  return result;
}
