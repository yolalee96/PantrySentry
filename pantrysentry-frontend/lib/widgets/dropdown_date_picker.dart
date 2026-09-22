import 'package:flutter/material.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// A date picker using three dropdowns (Day / Month / Year) instead of a
/// calendar grid — Flutter's built-in showDatePicker only offers a year
/// dropdown, with month navigated one step at a time via arrows, which
/// isn't fast enough for picking an expiry date months away. Drop-in
/// replacement: same call signature/return type as showDatePicker.
Future<DateTime?> showDropdownDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (context) => _DropdownDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

class _DropdownDatePickerDialog extends StatefulWidget {
  const _DropdownDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_DropdownDatePickerDialog> createState() => _DropdownDatePickerDialogState();
}

class _DropdownDatePickerDialogState extends State<_DropdownDatePickerDialog> {
  late int _day;
  late int _month;
  late int _year;

  @override
  void initState() {
    super.initState();
    final clamped = widget.initialDate.isBefore(widget.firstDate)
        ? widget.firstDate
        : widget.initialDate.isAfter(widget.lastDate)
            ? widget.lastDate
            : widget.initialDate;
    _day = clamped.day;
    _month = clamped.month;
    _year = clamped.year;
  }

  List<int> get _availableYears =>
      [for (var y = widget.firstDate.year; y <= widget.lastDate.year; y++) y];

  List<int> get _availableMonths {
    // If the selected year is the first/last allowed year, restrict
    // months to what's actually in range rather than letting the user
    // pick a month that would fall outside firstDate/lastDate.
    var start = 1;
    var end = 12;
    if (_year == widget.firstDate.year) start = widget.firstDate.month;
    if (_year == widget.lastDate.year) end = widget.lastDate.month;
    return [for (var m = start; m <= end; m++) m];
  }

  List<int> get _availableDays {
    final maxDay = _daysInMonth(_year, _month);
    var start = 1;
    var end = maxDay;
    if (_year == widget.firstDate.year && _month == widget.firstDate.month) start = widget.firstDate.day;
    if (_year == widget.lastDate.year && _month == widget.lastDate.month) end = widget.lastDate.day.clamp(1, maxDay);
    return [for (var d = start; d <= end; d++) d];
  }

  void _clampSelections() {
    if (!_availableMonths.contains(_month)) _month = _availableMonths.first;
    final maxDay = _daysInMonth(_year, _month);
    if (_day > maxDay) _day = maxDay;
    if (!_availableDays.contains(_day)) _day = _availableDays.first;
  }

  @override
  Widget build(BuildContext context) {
    _clampSelections();
    return AlertDialog(
      title: const Text('Select date'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _day,
              decoration: const InputDecoration(labelText: 'Day', isDense: true),
              items: _availableDays.map((d) => DropdownMenuItem(value: d, child: Text('$d'))).toList(),
              onChanged: (v) => setState(() => _day = v ?? _day),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<int>(
              initialValue: _month,
              decoration: const InputDecoration(labelText: 'Month', isDense: true),
              items: _availableMonths
                  .map((m) => DropdownMenuItem(value: m, child: Text(_monthNames[m - 1], overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _month = v ?? _month),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _year,
              decoration: const InputDecoration(labelText: 'Year', isDense: true),
              items: _availableYears.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
              onChanged: (v) => setState(() => _year = v ?? _year),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(DateTime(_year, _month, _day)),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
