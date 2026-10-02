import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/attendance_service.dart';
import '../services/auth_service.dart';
import '../utils/dialogs.dart';
import '../utils/ist_helper.dart';

class ApplyTimeOffScreen extends StatefulWidget {
  final VoidCallback? onSuccess;
  final Map<String, dynamic>? existingRequest;

  const ApplyTimeOffScreen({super.key, this.onSuccess, this.existingRequest});

  @override
  State<ApplyTimeOffScreen> createState() => _ApplyTimeOffScreenState();
}

class _ApplyTimeOffScreenState extends State<ApplyTimeOffScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isLoading = false;

  TimeOfDay _officeStartTime = const TimeOfDay(hour: 9, minute: 30);
  TimeOfDay _officeEndTime = const TimeOfDay(hour: 18, minute: 30);
  String? _todayAttendanceStatus;
  Map<DateTime, String> _holidaysMap = {};

  @override
  void initState() {
    super.initState();
    _loadOfficeHours();
    _checkTodayAttendanceStatus();
    _fetchHolidays();
    if (widget.existingRequest != null) {
      _initializeForEdit();
    } else {
      // Clear data for new request
      _selectedDate = null;
      _startTime = null;
      _endTime = null;
      _reasonController.text = '';
    }
  }

  Future<void> _fetchHolidays() async {
    try {
      final service = Provider.of<AttendanceService>(context, listen: false);
      final map = await service.getHolidaysMap();
      final Map<DateTime, String> dtMap = {};
      map.forEach((k, v) {
        try {
          final p = k.split('-');
          if (p.length == 3) {
            dtMap[DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]))] = v;
          }
        } catch (_) {}
      });
      if (mounted) {
        setState(() {
          _holidaysMap = dtMap;
        });
      }
    } catch (e) {
      print('Error fetching holidays in timeoff: $e');
    }
  }

  bool get _isSelectedDateHoliday {
    if (_selectedDate == null) return false;
    final d = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
    return _holidaysMap.containsKey(d);
  }

  bool _isCurrentlyCheckedIn = false;

  Future<void> _checkTodayAttendanceStatus() async {
    try {
      final service = Provider.of<AttendanceService>(context, listen: false);
      final todayData = await service.getMyTodayAttendance();
      if (mounted) {
        setState(() {
          _todayAttendanceStatus = todayData['status'];
          _isCurrentlyCheckedIn = todayData['checkedIn'] == true || todayData['status'] == 'CHECKED_IN';
        });
      }
    } catch (e) {
      print('Error fetching today attendance via getMyTodayAttendance: $e');
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        final email = authService.userEmail;
        if (email != null && email.isNotEmpty) {
          final service = Provider.of<AttendanceService>(context, listen: false);
          final statusRes = await service.getTodayAttendanceStatus(email);
          if (mounted) {
            setState(() {
              _todayAttendanceStatus = statusRes['status'];
              _isCurrentlyCheckedIn = statusRes['status'] == 'CHECKED_IN';
            });
          }
        }
      } catch (e2) {
        print('Error in fallback today attendance: $e2');
      }
    }
  }

  Future<void> _loadOfficeHours() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final settings = await AuthService.fetchGlobalSettings(token: authService.token);
      String? startStr;
      String? endStr;
      if (settings != null) {
        startStr = settings['office_start_time'];
        endStr = settings['office_end_time'];
        final prefs = await SharedPreferences.getInstance();
        if (startStr != null) await prefs.setString('office_start_time', startStr);
        if (endStr != null) await prefs.setString('office_end_time', endStr);
      } else {
        final prefs = await SharedPreferences.getInstance();
        startStr = prefs.getString('office_start_time');
        endStr = prefs.getString('office_end_time');
      }

      if (startStr != null && startStr.contains(':')) {
        final parts = startStr.split(':');
        _officeStartTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
      if (endStr != null && endStr.contains(':')) {
        final parts = endStr.split(':');
        _officeEndTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
      if (mounted) setState(() {});
    } catch (e) {
      print('Error loading office hours: $e');
    }
  }

  void _initializeForEdit() {
    final req = widget.existingRequest!;
    _reasonController.text = req['subtitle'] ?? ''; // Assuming subtitle holds reason for now or fetch detail
    if (req['reason'] != null) _reasonController.text = req['reason'];

    try {
      _selectedDate = ISTHelper.parseUTCtoIST(req['date']);
      // Parse times (HH:mm:ss)
      final startParts = req['start_time'].split(':');
      final endParts = req['end_time'].split(':');
      
      _startTime = TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1]));
      _endTime = TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1]));
    } catch (e) {
      print('Error parsing existing request: $e');
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime now = ISTHelper.now();
    DateTime initialDate = _selectedDate ?? now;
    
    // Advance initialDate if it falls on Sunday or a company holiday
    while (initialDate.weekday == DateTime.sunday || _holidaysMap.containsKey(DateTime(initialDate.year, initialDate.month, initialDate.day))) {
      initialDate = initialDate.add(const Duration(days: 1));
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      selectableDayPredicate: (DateTime day) {
        final d = DateTime(day.year, day.month, day.day);
        // Disable Sundays and company holidays
        if (day.weekday == DateTime.sunday) return false;
        if (_holidaysMap.containsKey(d)) return false;
        return true;
      },
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B82F6),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (!mounted) return;
    if (picked != null && picked != _selectedDate) {
      if (picked.weekday == DateTime.sunday) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sundays are not allowed for time-off requests')),
        );
        return;
      }
      final pDate = DateTime(picked.year, picked.month, picked.day);
      if (_holidaysMap.containsKey(pDate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Selected date is a company holiday (${_holidaysMap[pDate]}). Time-off cannot be requested.')),
        );
        return;
      }
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return ISTHelper.formatTime(dt);
  }

  bool get _isOutsideOfficeHours {
    final officeStartMinutes = _officeStartTime.hour * 60 + _officeStartTime.minute;
    final officeEndMinutes = _officeEndTime.hour * 60 + _officeEndTime.minute;

    if (_startTime != null) {
      final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
      if (startMinutes < officeStartMinutes || startMinutes >= officeEndMinutes) {
        return true;
      }
    }
    if (_endTime != null) {
      final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
      if (endMinutes <= officeStartMinutes || endMinutes > officeEndMinutes) {
        return true;
      }
    }
    return false;
  }

  bool get _isSelectedDateToday {
    if (_selectedDate == null) return false;
    final now = ISTHelper.now();
    return _selectedDate!.year == now.year &&
        _selectedDate!.month == now.month &&
        _selectedDate!.day == now.day;
  }

  bool get _isCurrentlyCheckedInToday {
    return _isSelectedDateToday && (_isCurrentlyCheckedIn || _todayAttendanceStatus == 'CHECKED_IN');
  }

  Future<void> _selectTime(bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart 
          ? (_startTime ?? _officeStartTime)
          : (_endTime ?? _officeEndTime),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF3B82F6),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (!mounted) return;
    if (picked != null) {
      setState(() {
        final officeStartMinutes = _officeStartTime.hour * 60 + _officeStartTime.minute;
        final officeEndMinutes = _officeEndTime.hour * 60 + _officeEndTime.minute;
        final pickedMinutes = picked.hour * 60 + picked.minute;

        if (isStart) {
          _startTime = picked;
          if (pickedMinutes < officeStartMinutes || pickedMinutes >= officeEndMinutes) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Start time must be within office hours (${_formatTimeOfDay(_officeStartTime)} - ${_formatTimeOfDay(_officeEndTime)})'),
                backgroundColor: Colors.red[700],
              ),
            );
          }
          // Auto set end time to start + 2 hours clamped to officeEnd
          if (_endTime == null || (_endTime!.hour * 60 + _endTime!.minute <= pickedMinutes)) {
            final targetMinutes = pickedMinutes + 120;
            final clampedMinutes = targetMinutes > officeEndMinutes ? officeEndMinutes : targetMinutes;
            _endTime = TimeOfDay(hour: clampedMinutes ~/ 60, minute: clampedMinutes % 60);
          }
        } else {
          _endTime = picked;
          if (pickedMinutes <= officeStartMinutes || pickedMinutes > officeEndMinutes) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('End time must be within office hours (${_formatTimeOfDay(_officeStartTime)} - ${_formatTimeOfDay(_officeEndTime)})'),
                backgroundColor: Colors.red[700],
              ),
            );
          }
        }
      });
    }
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return 'Select Time';
    return _formatTimeOfDay(time);
  }

  String _calculateDuration() {
    if (_startTime == null || _endTime == null) return '';
    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
    
    int diff = endMinutes - startMinutes;
    if (diff <= 0) return 'Invalid duration';
    
    final hours = diff ~/ 60;
    final minutes = diff % 60;
    
    if (hours > 0 && minutes > 0) return '$hours hr $minutes min';
    if (hours > 0) return '$hours hr';
    return '$minutes min';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedDate == null) {
      showErrorDialog(context, 'Please select a date');
      return;
    }

    if (_isCurrentlyCheckedInToday) {
      showErrorDialog(
        context,
        'You are currently checked in today. Time-off can only be applied after checking out for the day.',
      );
      return;
    }
    if (_startTime == null || _endTime == null) {
      showErrorDialog(context, 'Please select start and end times');
      return;
    }

    // Validate times
    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
    final officeStartMinutes = _officeStartTime.hour * 60 + _officeStartTime.minute;
    final officeEndMinutes = _officeEndTime.hour * 60 + _officeEndTime.minute;

    if (endMinutes <= startMinutes) {
      showErrorDialog(context, 'End time must be after start time');
      return;
    }

    if (startMinutes < officeStartMinutes || startMinutes >= officeEndMinutes) {
      showErrorDialog(
        context,
        'Start time (${_formatTime(_startTime)}) must be within configured office hours (${_formatTimeOfDay(_officeStartTime)} - ${_formatTimeOfDay(_officeEndTime)}). Requests outside office hours are not allowed.',
      );
      return;
    }

    if (endMinutes <= officeStartMinutes || endMinutes > officeEndMinutes) {
      showErrorDialog(
        context,
        'End time (${_formatTime(_endTime)}) must be within configured office hours (${_formatTimeOfDay(_officeStartTime)} - ${_formatTimeOfDay(_officeEndTime)}). Requests outside office hours are not allowed.',
      );
      return;
    }

    if (_isSelectedDateHoliday) {
      final d = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
      showErrorDialog(context, 'Selected date is a company holiday (${_holidaysMap[d]}). Time-off cannot be requested.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final service = Provider.of<AttendanceService>(context, listen: false);
      
      if (widget.existingRequest != null) {
        await service.updateTimeOff(
          widget.existingRequest!['id'],
          _selectedDate!,
          _startTime!,
          _endTime!,
          _reasonController.text,
        );
      } else {
        await service.applyTimeOff(
          _selectedDate!,
          _startTime!,
          _endTime!,
          _reasonController.text,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.existingRequest != null ? 'Request updated successfully' : 'Time-off requested successfully')),
        );
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        var msg = e.toString().replaceAll('Exception: ', '');
        showErrorDialog(context, msg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingRequest != null ? 'Edit Time-Off' : 'Apply Time-Off'),
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else if (widget.onSuccess != null) {
              widget.onSuccess!();
            }
          },
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Office Hours info banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: Color(0xFF16A34A)),
                    const SizedBox(width: 8),
                    Text(
                      'Office Hours: ${_formatTimeOfDay(_officeStartTime)} - ${_formatTimeOfDay(_officeEndTime)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Date Selection
              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _selectedDate != null
                        ? ISTHelper.formatDate(_selectedDate!)
                        : 'Select Date',
                    style: TextStyle(
                      color: _selectedDate != null ? Colors.black87 : Colors.grey[600],
                    ),
                  ),
                ),
              ),
              if (_isSelectedDateHoliday)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEEBEE),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFC1272D)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFC1272D), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Selected date is a company holiday (${_holidaysMap[DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day)]}). Time-off cannot be requested.',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFC1272D),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_isCurrentlyCheckedInToday)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline, color: Color(0xFFB45309), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You are currently checked in today. Time-off can only be applied after checking out for the day.',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),

              // Time Selection Row
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectTime(true),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Start Time',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.access_time),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _startTime != null &&
                                      (_startTime!.hour * 60 + _startTime!.minute < _officeStartTime.hour * 60 + _officeStartTime.minute ||
                                          _startTime!.hour * 60 + _startTime!.minute >= _officeEndTime.hour * 60 + _officeEndTime.minute)
                                  ? Colors.red
                                  : Colors.grey[400]!,
                            ),
                          ),
                        ),
                        child: Text(
                          _formatTime(_startTime),
                          style: TextStyle(
                            color: _startTime != null ? Colors.black87 : Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectTime(false),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'End Time',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.access_time_filled),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _endTime != null &&
                                      (_endTime!.hour * 60 + _endTime!.minute <= _officeStartTime.hour * 60 + _officeStartTime.minute ||
                                          _endTime!.hour * 60 + _endTime!.minute > _officeEndTime.hour * 60 + _officeEndTime.minute)
                                  ? Colors.red
                                  : Colors.grey[400]!,
                            ),
                          ),
                        ),
                        child: Text(
                          _formatTime(_endTime),
                          style: TextStyle(
                            color: _endTime != null ? Colors.black87 : Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              if (_isOutsideOfficeHours)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 16, color: Colors.red[700]),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Time-off must be within office hours (${_formatTimeOfDay(_officeStartTime)} - ${_formatTimeOfDay(_officeEndTime)}). Any time beyond is not allowed.',
                            style: TextStyle(fontSize: 11, color: Colors.red[700], fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_startTime != null && _endTime != null && !_isOutsideOfficeHours)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, left: 4),
                  child: Text(
                    'Duration: ${_calculateDuration()}',
                    style: const TextStyle(
                      color: Color(0xFF3B82F6),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Reason
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                validator: (value) => value == null || value.trim().isEmpty ? 'Please enter a reason' : null,
              ),

              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: (_isLoading || _isOutsideOfficeHours || _isCurrentlyCheckedInToday || _isSelectedDateHoliday) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20, 
                        width: 20, 
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      )
                    : Text(widget.existingRequest != null ? 'Update Request' : 'Submit Request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

