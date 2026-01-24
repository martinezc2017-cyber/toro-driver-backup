import 'package:flutter/material.dart';

/// Custom Email Keyboard for email input fields
class CustomEmailKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onDone;
  final VoidCallback? onChanged;

  const CustomEmailKeyboard({
    super.key,
    required this.controller,
    this.onDone,
    this.onChanged,
  });

  @override
  State<CustomEmailKeyboard> createState() => _CustomEmailKeyboardState();
}

class _CustomEmailKeyboardState extends State<CustomEmailKeyboard> {
  void _insertText(String text) {
    final value = controller.value;
    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      controller.text += text;
    } else {
      final newText = value.text.replaceRange(start, end, text);
      controller.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + text.length),
      );
    }
    widget.onChanged?.call();
  }

  TextEditingController get controller => widget.controller;

  Widget _buildKey(String char, {double width = 1.0, Color? color}) {
    return Expanded(
      flex: (width * 10).toInt(),
      child: Container(
        margin: const EdgeInsets.all(3),
        child: ElevatedButton(
          onPressed: () => _insertText(char),
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? const Color(0xFF1F2937),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFF374151), width: 1),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            minimumSize: const Size(0, 36),
            elevation: 0,
          ),
          child: Text(
            char,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick access buttons
          Row(
            children: [
              _buildKey('@', color: const Color(0xFF2563EB)),
              _buildKey('.com', color: const Color(0xFF2563EB)),
              _buildKey('.es', color: const Color(0xFF2563EB)),
            ],
          ),
          // QWERTY rows
          Row(
            children: [
              _buildKey('q'),
              _buildKey('w'),
              _buildKey('e'),
              _buildKey('r'),
              _buildKey('t'),
              _buildKey('y'),
              _buildKey('u'),
              _buildKey('i'),
              _buildKey('o'),
              _buildKey('p'),
            ],
          ),
          Row(
            children: [
              _buildKey('a', width: 0.8),
              _buildKey('s'),
              _buildKey('d'),
              _buildKey('f'),
              _buildKey('g'),
              _buildKey('h'),
              _buildKey('j'),
              _buildKey('k'),
              _buildKey('l', width: 0.8),
            ],
          ),
          Row(
            children: [
              _buildKey('z'),
              _buildKey('x'),
              _buildKey('c'),
              _buildKey('v'),
              _buildKey('b'),
              _buildKey('n'),
              _buildKey('m'),
              _buildKey('_'),
              _buildKey('-'),
            ],
          ),
          // Space and Done
          Row(
            children: [
              Expanded(
                flex: 60,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  child: ElevatedButton(
                    onPressed: () => _insertText(' '),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2937),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Color(0xFF374151), width: 1),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: const Size(0, 36),
                      elevation: 0,
                    ),
                    child: const Text('espacio', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ),
              Expanded(
                flex: 40,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  child: ElevatedButton(
                    onPressed: () => widget.onDone?.call(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      minimumSize: const Size(0, 36),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, size: 14),
                        SizedBox(width: 4),
                        Text('Listo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom Text Keyboard for general text input
class CustomTextKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onDone;
  final VoidCallback? onChanged;

  const CustomTextKeyboard({
    super.key,
    required this.controller,
    this.onDone,
    this.onChanged,
  });

  @override
  State<CustomTextKeyboard> createState() => _CustomTextKeyboardState();
}

class _CustomTextKeyboardState extends State<CustomTextKeyboard> {
  bool isShift = false;

  void _insertText(String text) {
    final value = controller.value;
    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      controller.text += text;
    } else {
      final newText = value.text.replaceRange(start, end, text);
      controller.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + text.length),
      );
    }

    if (isShift) {
      setState(() => isShift = false);
    }
    widget.onChanged?.call();
  }

  void _handleBackspace() {
    final value = controller.value;
    if (value.text.isEmpty) return;

    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      controller.text = value.text.substring(0, value.text.length - 1);
    } else if (start == end) {
      controller.value = value.copyWith(
        text: value.text.replaceRange(start - 1, end, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      controller.value = value.copyWith(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    widget.onChanged?.call();
  }

  TextEditingController get controller => widget.controller;

  Widget _buildKey(String char, {double width = 1.0}) {
    return Expanded(
      flex: (width * 10).toInt(),
      child: Container(
        margin: const EdgeInsets.all(3),
        child: ElevatedButton(
          onPressed: () => _insertText(isShift ? char.toUpperCase() : char),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1F2937),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFF374151), width: 1),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            minimumSize: const Size(0, 34),
            elevation: 0,
          ),
          child: Text(
            isShift ? char.toUpperCase() : char,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildKey('q'),
              _buildKey('w'),
              _buildKey('e'),
              _buildKey('r'),
              _buildKey('t'),
              _buildKey('y'),
              _buildKey('u'),
              _buildKey('i'),
              _buildKey('o'),
              _buildKey('p'),
            ],
          ),
          Row(
            children: [
              _buildKey('a', width: 0.8),
              _buildKey('s'),
              _buildKey('d'),
              _buildKey('f'),
              _buildKey('g'),
              _buildKey('h'),
              _buildKey('j'),
              _buildKey('k'),
              _buildKey('l', width: 0.8),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 8,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  child: ElevatedButton(
                    onPressed: () => setState(() => isShift = !isShift),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isShift ? const Color(0xFF2563EB) : const Color(0xFF1F2937),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isShift ? const Color(0xFF2563EB) : const Color(0xFF374151),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 34),
                      elevation: 0,
                    ),
                    child: const Icon(Icons.arrow_upward, size: 14),
                  ),
                ),
              ),
              _buildKey('z'),
              _buildKey('x'),
              _buildKey('c'),
              _buildKey('v'),
              _buildKey('b'),
              _buildKey('n'),
              _buildKey('m'),
              Expanded(
                flex: 8,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  child: ElevatedButton(
                    onPressed: _handleBackspace,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2937),
                      foregroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Color(0xFF374151), width: 1),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 34),
                      elevation: 0,
                    ),
                    child: const Icon(Icons.backspace_outlined, size: 14),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 60,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  child: ElevatedButton(
                    onPressed: () => _insertText(' '),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2937),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Color(0xFF374151), width: 1),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 34),
                      elevation: 0,
                    ),
                    child: const Text('espacio', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ),
              Expanded(
                flex: 40,
                child: Container(
                  margin: const EdgeInsets.all(3),
                  child: ElevatedButton(
                    onPressed: () => widget.onDone?.call(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 34),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, size: 13),
                        SizedBox(width: 4),
                        Text('Listo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom Numeric Keyboard
class CustomNumericKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onDone;
  final VoidCallback? onChanged;

  const CustomNumericKeyboard({
    super.key,
    required this.controller,
    this.onDone,
    this.onChanged,
  });

  @override
  State<CustomNumericKeyboard> createState() => _CustomNumericKeyboardState();
}

class _CustomNumericKeyboardState extends State<CustomNumericKeyboard> {
  void _insertText(String text) {
    final value = controller.value;
    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      controller.text += text;
    } else {
      final newText = value.text.replaceRange(start, end, text);
      controller.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + text.length),
      );
    }
    widget.onChanged?.call();
  }

  void _handleBackspace() {
    final value = controller.value;
    if (value.text.isEmpty) return;

    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      controller.text = value.text.substring(0, value.text.length - 1);
    } else if (start == end) {
      controller.value = value.copyWith(
        text: value.text.replaceRange(start - 1, end, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      controller.value = value.copyWith(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    widget.onChanged?.call();
  }

  TextEditingController get controller => widget.controller;

  Widget _buildKey(String char, {double width = 1.0, Color? color}) {
    return Expanded(
      flex: (width * 10).toInt(),
      child: Container(
        margin: const EdgeInsets.all(6),
        child: ElevatedButton(
          onPressed: () => _insertText(char),
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? const Color(0xFF1F2937),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF374151), width: 1),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
          ),
          child: Text(
            char,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [_buildKey('1'), _buildKey('2'), _buildKey('3')]),
          Row(children: [_buildKey('4'), _buildKey('5'), _buildKey('6')]),
          Row(children: [_buildKey('7'), _buildKey('8'), _buildKey('9')]),
          Row(
            children: [
              _buildKey('.', color: const Color(0xFF2563EB)),
              _buildKey('0'),
              Expanded(
                flex: 10,
                child: Container(
                  margin: const EdgeInsets.all(6),
                  child: ElevatedButton(
                    onPressed: _handleBackspace,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2937),
                      foregroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFF374151), width: 1),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Icon(Icons.backspace_outlined, size: 18),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(6),
                  child: ElevatedButton(
                    onPressed: () => widget.onDone?.call(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, size: 18),
                        SizedBox(width: 8),
                        Text('Listo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Custom Phone Keyboard
class CustomPhoneKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onDone;
  final VoidCallback? onChanged;

  const CustomPhoneKeyboard({
    super.key,
    required this.controller,
    this.onDone,
    this.onChanged,
  });

  @override
  State<CustomPhoneKeyboard> createState() => _CustomPhoneKeyboardState();
}

class _CustomPhoneKeyboardState extends State<CustomPhoneKeyboard> {
  void _insertText(String text) {
    final value = controller.value;
    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      controller.text += text;
    } else {
      final newText = value.text.replaceRange(start, end, text);
      controller.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + text.length),
      );
    }
    widget.onChanged?.call();
  }

  void _handleBackspace() {
    final value = controller.value;
    if (value.text.isEmpty) return;

    final start = value.selection.baseOffset;
    final end = value.selection.extentOffset;

    if (start < 0) {
      controller.text = value.text.substring(0, value.text.length - 1);
    } else if (start == end) {
      controller.value = value.copyWith(
        text: value.text.replaceRange(start - 1, end, ''),
        selection: TextSelection.collapsed(offset: start - 1),
      );
    } else {
      controller.value = value.copyWith(
        text: value.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start),
      );
    }
    widget.onChanged?.call();
  }

  TextEditingController get controller => widget.controller;

  Widget _buildKey(String char, {double width = 1.0, Color? color}) {
    return Expanded(
      flex: (width * 10).toInt(),
      child: Container(
        margin: const EdgeInsets.all(6),
        child: ElevatedButton(
          onPressed: () => _insertText(char),
          style: ElevatedButton.styleFrom(
            backgroundColor: color ?? const Color(0xFF1F2937),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFF374151), width: 1),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
          ),
          child: Text(
            char,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [_buildKey('1'), _buildKey('2'), _buildKey('3')]),
          Row(children: [_buildKey('4'), _buildKey('5'), _buildKey('6')]),
          Row(children: [_buildKey('7'), _buildKey('8'), _buildKey('9')]),
          Row(
            children: [
              _buildKey('*', color: const Color(0xFF2563EB)),
              _buildKey('0'),
              _buildKey('#', color: const Color(0xFF2563EB)),
            ],
          ),
          Row(
            children: [
              _buildKey('+'),
              _buildKey('('),
              _buildKey(')'),
              _buildKey('-'),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 50,
                child: Container(
                  margin: const EdgeInsets.all(6),
                  child: ElevatedButton(
                    onPressed: _handleBackspace,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F2937),
                      foregroundColor: Colors.redAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFF374151), width: 1),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Icon(Icons.backspace_outlined, size: 18),
                  ),
                ),
              ),
              Expanded(
                flex: 50,
                child: Container(
                  margin: const EdgeInsets.all(6),
                  child: ElevatedButton(
                    onPressed: () => widget.onDone?.call(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Listo', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
