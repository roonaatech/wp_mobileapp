import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/attendance_service.dart';
import '../utils/dialogs.dart';

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

  @override
  void initState() {
    super.initState();
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

  void _initializeForEdit() {
    final req = widget.existingRequest!;
    _reasonController.text = req['subtitle'] ?? ''; // Assuming subtitle holds reason for now or fetch detail
    // TODO: Verify where reason comes from in list item. Usually it's in 'reason' or 'subtitle'
    if (req['reason'] != null) _reasonController.text = req['reason'];

    try {
      _selectedDate = DateTime.parse(req['date']);
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
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(), // Can't apply for past dates usually? Or maybe allow it?
      lastDate: DateTime.now().add(const Duration(days: 90)),
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
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime(bool isStart) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart 
          ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
          : (_endTime ?? const TimeOfDay(hour: 18, minute: 0)),
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
    
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
          // Auto set end time to start + 1 hour if not set or invalid
          if (_endTime == null || (_endTime!.hour < picked.hour) || (_endTime!.hour == picked.hour && _endTime!.minute <= picked.minute)) {
             _endTime = TimeOfDay(hour: (picked.hour + 2) % 24, minute: picked.minute);
          }
        } else {
          _endTime = picked;
        }
      });
    }
  }

  String _formatTime(TimeOfDay? time) {
    if (time == null) return 'Select Time';
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    return DateFormat('hh:mm a').format(dt);
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
    if (_startTime == null || _endTime == null) {
      showErrorDialog(context, 'Please select start and end times');
      return;
    }

    // Validate times
    final startMinutes = _startTime!.hour * 60 + _startTime!.minute;
    final endMinutes = _endTime!.hour * 60 + _endTime!.minute;
    if (endMinutes <= startMinutes) {
      showErrorDialog(context, 'End time must be after start time');
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
                        ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
                        : 'Select Date',
                    style: TextStyle(
                      color: _selectedDate != null ? Colors.black87 : Colors.grey[600],
                    ),
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
                        decoration: const InputDecoration(
                          labelText: 'Start Time',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.access_time),
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
                        decoration: const InputDecoration(
                          labelText: 'End Time',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.access_time_filled),
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
              
              if (_startTime != null && _endTime != null)
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
                onPressed: _isLoading ? null : _submit,
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
