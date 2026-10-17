import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/attendance_service.dart';
import '../utils/ist_helper.dart';
import '../utils/dialogs.dart';

class OnDutyScreen extends StatefulWidget {
  final VoidCallback? onVisitEnded;
  final Map<String, dynamic>? existingLog;

  const OnDutyScreen({super.key, this.onVisitEnded, this.existingLog});

  @override
  State<OnDutyScreen> createState() => _OnDutyScreenState();
}

class _OnDutyScreenState extends State<OnDutyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clientController = TextEditingController();
  final _locationController = TextEditingController();
  final _purposeController = TextEditingController();
  final _endLocationController = TextEditingController();
  bool _isLoading = false;
  bool _isOnDuty = false;
  int? _activeOnDutyId;
  DateTime? _startTime;
  bool _isTodayHoliday = false;
  String? _todayHolidayName;

  DateTime? _editStartTime;
  DateTime? _editEndTime;
  DateTime? _editCompletedEndTime;
  DateTime? _selectedEndDate;
  TimeOfDay? _selectedEndTime;

  @override
  void initState() {
    super.initState();
    _checkTodayHoliday();
    if (widget.existingLog != null) {
      _initializeForEdit();
    } else {
      _checkActiveOnDuty();
    }
  }

  Future<void> _checkTodayHoliday() async {
    try {
      final service = Provider.of<AttendanceService>(context, listen: false);
      final map = await service.getHolidaysMap();
      final now = ISTHelper.now();
      final todayStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      if (map.containsKey(todayStr)) {
        if (mounted) {
          setState(() {
            _isTodayHoliday = true;
            _todayHolidayName = map[todayStr];
          });
        }
      }
    } catch (e) {
      print('Error checking holiday in on-duty: $e');
    }
  }

  @override
  void didUpdateWidget(covariant OnDutyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If existingLog changed or widget was updated, reinitialize
    if (oldWidget.existingLog != widget.existingLog) {
      if (widget.existingLog != null) {
        _initializeForEdit();
      } else {
        _clearForm();
        _checkActiveOnDuty();
      }
    }
  }

  void _clearForm() {
    _clientController.clear();
    _locationController.clear();
    _purposeController.clear();
    _endLocationController.clear();
    _startTime = null;
    _isOnDuty = false;
    _activeOnDutyId = null;
    _editStartTime = null;
    _editEndTime = null;
    _editCompletedEndTime = null;
    _selectedEndDate = null;
    _selectedEndTime = null;
  }

  void _initializeForEdit() {
    final log = widget.existingLog!;
    _clientController.text = log['client_name'] ?? (log['title']?.startsWith('On-Duty: ') == true ? log['title'].substring(9) : '');
    _locationController.text = log['location'] ?? '';
    _endLocationController.text = log['end_location'] ?? '';
    _purposeController.text = log['purpose'] ?? '';
    if (_locationController.text.isEmpty && log['subtitle'] != null) {
      String subtitle = log['subtitle'] ?? '';
      List<String> parts = subtitle.split(' - ');
      if (parts.isNotEmpty) {
        String locationPart = parts[0];
        if (locationPart.contains(' to ')) {
          List<String> locs = locationPart.split(' to ');
          _locationController.text = locs[0];
          _endLocationController.text = locs.sublist(1).join(' to ');
        } else {
          _locationController.text = locationPart;
        }
        if (parts.length > 1) {
          _purposeController.text = parts.sublist(1).join(' - ');
        }
      }
    }

    final startStr = log['start_time'] ?? log['start'] ?? '';
    final endStr = log['end_time'] ?? log['end'] ?? '';
    final completedStr = log['completed_end_time'] ?? endStr;

    if (startStr.toString().isNotEmpty) {
      _editStartTime = ISTHelper.parseUTCtoAppTimezone(startStr.toString());
    }
    if (endStr.toString().isNotEmpty) {
      _editEndTime = ISTHelper.parseUTCtoAppTimezone(endStr.toString());
      if (_editEndTime != null) {
        _selectedEndDate = DateTime(_editEndTime!.year, _editEndTime!.month, _editEndTime!.day);
        _selectedEndTime = TimeOfDay(hour: _editEndTime!.hour, minute: _editEndTime!.minute);
      }
    }
    if (completedStr.toString().isNotEmpty) {
      _editCompletedEndTime = ISTHelper.parseUTCtoAppTimezone(completedStr.toString());
    } else {
      _editCompletedEndTime = _editEndTime;
    }
  }

  Future<void> _pickEndDate() async {
    final initial = _selectedEndDate ?? (_editStartTime ?? ISTHelper.now());
    final firstDate = _editStartTime != null
        ? DateTime(_editStartTime!.year, _editStartTime!.month, _editStartTime!.day)
        : DateTime(2020);
    final lastDate = _editCompletedEndTime != null
        ? DateTime(_editCompletedEndTime!.year, _editCompletedEndTime!.month, _editCompletedEndTime!.day)
        : ISTHelper.now();

    final safeLast = lastDate.isBefore(firstDate) ? firstDate : lastDate;
    final safeInitial = initial.isBefore(firstDate)
        ? firstDate
        : (initial.isAfter(safeLast) ? safeLast : initial);

    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: firstDate,
      lastDate: safeLast,
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
        _selectedEndDate = picked;
      });
    }
  }

  Future<void> _pickEndTime() async {
    final initial = _selectedEndTime ?? TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
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
        _selectedEndTime = picked;
      });
    }
  }

  Future<void> _updateOnDuty() async {
    if (!_formKey.currentState!.validate()) return;

    String? formattedEndTime;
    if (_selectedEndTime != null) {
      if (_selectedEndDate == null) {
        showErrorDialog(context, 'Please select an end date.');
        return;
      }

      final chosenDateTime = DateTime(
        _selectedEndDate!.year,
        _selectedEndDate!.month,
        _selectedEndDate!.day,
        _selectedEndTime!.hour,
        _selectedEndTime!.minute,
      );

      // Validation 1: End time must be after start time
      if (_editStartTime != null) {
        final compareStart = DateTime(
          _editStartTime!.year,
          _editStartTime!.month,
          _editStartTime!.day,
          _editStartTime!.hour,
          _editStartTime!.minute,
        );
        if (!chosenDateTime.isAfter(compareStart)) {
          showErrorDialog(
            context,
            'End time must be after start time (${ISTHelper.formatDateTime(_editStartTime!)}).',
          );
          return;
        }
      }

      // Validation 2: End time cannot be greater than completed end time
      if (_editCompletedEndTime != null) {
        final compareCompleted = DateTime(
          _editCompletedEndTime!.year,
          _editCompletedEndTime!.month,
          _editCompletedEndTime!.day,
          _editCompletedEndTime!.hour,
          _editCompletedEndTime!.minute,
          _editCompletedEndTime!.second,
        );
        if (chosenDateTime.isAfter(compareCompleted)) {
          showErrorDialog(
            context,
            'End time cannot be greater than the end time already completed (${ISTHelper.formatDateTime(_editCompletedEndTime!)}).',
          );
          return;
        }
      }

      final y = _selectedEndDate!.year.toString().padLeft(4, '0');
      final m = _selectedEndDate!.month.toString().padLeft(2, '0');
      final d = _selectedEndDate!.day.toString().padLeft(2, '0');
      final hh = _selectedEndTime!.hour.toString().padLeft(2, '0');
      final mm = _selectedEndTime!.minute.toString().padLeft(2, '0');
      formattedEndTime = '$y-$m-$d $hh:$mm:00';
    }

    setState(() => _isLoading = true);
    try {
      await Provider.of<AttendanceService>(context, listen: false).updateOnDutyDetails(
        widget.existingLog!['id'],
        _clientController.text,
        _locationController.text,
        _purposeController.text,
        _endLocationController.text,
        endTime: formattedEndTime,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('On-Duty Updated Successfully!')),
        );
        widget.onVisitEnded?.call();
      }
    } catch (error) {
       if (mounted) {
         showErrorDialog(context, 'Failed to update: $error');
       }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkActiveOnDuty() async {
    try {
      final result = await Provider.of<AttendanceService>(context, listen: false).getActiveOnDuty();
      if (result['active'] == true) {
        setState(() {
          _isOnDuty = true;
          _activeOnDutyId = result['data']['id'];
          _clientController.text = result['data']['client_name'] ?? '';
          _locationController.text = result['data']['location'] ?? '';
          _purposeController.text = result['data']['purpose'] ?? '';
          // Parse as UTC and convert to IST
          _startTime = ISTHelper.parseUTCtoIST(result['data']['start_time']);
        });
      }
    } catch (error) {
      // No active on-duty or error, stay in start mode
    }
  }

  Future<void> _startOnDuty() async {
    if (_isTodayHoliday) {
      showErrorDialog(context, 'Today is a company holiday ($_todayHolidayName). On-duty visits cannot be started today.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    try {
      await Provider.of<AttendanceService>(context, listen: false).startOnDuty(
        _clientController.text,
        _locationController.text,
        _purposeController.text,
      );
      setState(() {
        _isOnDuty = true;
        _startTime = ISTHelper.nowIST();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('On-Duty Started!')),
      );
    } catch (error) {
      showErrorDialog(context, 'Failed to start: $error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _endOnDuty() async {
    if (_endLocationController.text.trim().isEmpty) {
      showErrorDialog(context, 'Please enter End Location');
      return;
    }
    setState(() => _isLoading = true);
    try {
      await Provider.of<AttendanceService>(context, listen: false).endOnDuty(_endLocationController.text.trim());
      setState(() {
        _isOnDuty = false;
        _startTime = null;
      });
      _clearForm();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('On-Duty Ended!')),
      );
      // Notify parent to switch tab or refresh
      widget.onVisitEnded?.call();
    } catch (error) {
      showErrorDialog(context, 'Failed to end: $error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatDuration(DateTime start) {
    // Get current IST time for accurate duration calculation
    final currentIST = ISTHelper.nowIST();
    final duration = currentIST.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '$hours hr ${minutes} min';
    } else {
      return '$minutes min';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingLog != null;
    final title = isEditing ? 'Edit On-Duty' : 'On-Duty Visit';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else if (widget.onVisitEnded != null) {
              widget.onVisitEnded!();
            }
          },
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: isEditing
            ? _buildStartOnDutyForm() // Reuse form for editing
            : (_isOnDuty ? _buildActiveOnDutyView() : _buildStartOnDutyForm()),
      ),
    );
  }

  Widget _buildStartOnDutyForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isTodayHoliday && widget.existingLog == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.celebration, color: Color(0xFFB45309), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Today is a company holiday ($_todayHolidayName). On-duty visits cannot be started today.',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          TextFormField(
            controller: _clientController,
            decoration: InputDecoration(
              labelText: 'Client Name',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.business, color: Color(0xFF3B82F6)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please enter client name';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _locationController,
            decoration: InputDecoration(
              labelText: 'Start Location',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.location_on, color: Color(0xFF3B82F6)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please enter start location';
              return null;
            },
          ),
          if (widget.existingLog != null) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _endLocationController,
              decoration: InputDecoration(
                labelText: 'End Location',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.flag, color: Color(0xFF3B82F6)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Please enter end location';
                return null;
              },
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _purposeController,
            decoration: InputDecoration(
              labelText: 'Purpose of Visit',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.description, color: Color(0xFF3B82F6)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please enter purpose';
              return null;
            },
          ),
          if (widget.existingLog != null) ...[
            const SizedBox(height: 16),
            _buildEndTimeEditor(),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: (_isLoading || (_isTodayHoliday && widget.existingLog == null)) ? null : (widget.existingLog != null ? _updateOnDuty : _startOnDuty),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    widget.existingLog != null ? 'Update Details' : 'Start On-Duty',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndTimeEditor() {
    final completedTimeText = _editCompletedEndTime != null
        ? ISTHelper.formatDateTime(_editCompletedEndTime!)
        : null;

    final dateText = _selectedEndDate != null
        ? ISTHelper.formatDate(_selectedEndDate!)
        : 'Select Date';

    final timeText = _selectedEndTime != null
        ? ISTHelper.formatTime(DateTime(2020, 1, 1, _selectedEndTime!.hour, _selectedEndTime!.minute))
        : 'Select Time';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.schedule, size: 18, color: Color(0xFF3B82F6)),
              SizedBox(width: 8),
              Text(
                'End Date & Time',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Forgot to complete on time? You can adjust the end time earlier than when it was completed.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              height: 1.3,
            ),
          ),
          if (completedTimeText != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                border: Border.all(color: const Color(0xFFBFDBFE)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Completed at: $completedTimeText',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1D4ED8),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'End Date',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: _pickEndDate,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                dateText,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.calendar_today, size: 15, color: Color(0xFF3B82F6)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'End Time',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: _pickEndTime,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                timeText,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.access_time, size: 16, color: Color(0xFF3B82F6)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveOnDutyView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(Icons.timer_outlined, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              const Text(
                'Currently On-Duty',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              // Details
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.business, color: Colors.white, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Client',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                              Text(
                                _clientController.text,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Colors.white, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Start Location',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                              Text(
                                _locationController.text,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.description, color: Colors.white, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Purpose',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                              Text(
                                _purposeController.text,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        
        // Time Info
        if (_startTime != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          'Started at (${ISTHelper.getTimezoneName().split('/').last})',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ISTHelper.formatTime(DateTime(2000, 1, 1, _startTime!.hour, _startTime!.minute)),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 1,
                      height: 60,
                      color: Colors.blue.shade200,
                    ),
                    Column(
                      children: [
                        Text(
                          'Duration',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                        ),
                        const SizedBox(height: 4),
                        StreamBuilder(
                          stream: Stream.periodic(const Duration(seconds: 1)),
                          builder: (context, snapshot) {
                            return Text(
                              _formatDuration(_startTime!),
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        
        // End Location Input
        TextFormField(
          controller: _endLocationController,
          decoration: InputDecoration(
            labelText: 'End Location',
            hintText: 'Enter end location to complete visit',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: const Icon(Icons.flag, color: Color(0xFF3B82F6)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        
        // End Button
        ElevatedButton(
          onPressed: _isLoading ? null : _endOnDuty,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text(
                  'End On-Duty',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _clientController.dispose();
    _locationController.dispose();
    _purposeController.dispose();
    _endLocationController.dispose();
    super.dispose();
  }
}
