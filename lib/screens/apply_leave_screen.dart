import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/attendance_service.dart';

class ApplyLeaveScreen extends StatefulWidget {
  final VoidCallback? onSuccess;
  final Map<String, dynamic>? existingLeave;

  const ApplyLeaveScreen({super.key, this.onSuccess, this.existingLeave});

  @override
  State<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends State<ApplyLeaveScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String? _leaveType;
  bool _isLoading = false;
  List<dynamic> _leaveTypes = [];
  bool _fetchingTypes = true;
  int? _selectedLeaveAllowedDays;
  bool _hasOverlappingLeave = false;
  String? _overlapMessage;
  Map<String, dynamic> _userLeaveBalance = {};
  int? _selectedLeaveBalance = 0;

  // Calculate leave days excluding Sundays (Sunday = 0 in Dart)
  int _calculateLeaveDays(DateTime startDate, DateTime endDate) {
    if (startDate.isAfter(endDate)) return 0;
    int count = 0;
    DateTime current = startDate;
    while (!current.isAfter(endDate)) {
      // In Dart: Monday=1, Tuesday=2, ..., Sunday=7
      // Exclude Sunday (7)
      if (current.weekday != DateTime.sunday) {
        count++;
      }
      current = current.add(const Duration(days: 1));
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fetchLeaveTypes());
    Future.microtask(() => _fetchUserLeaveBalance());
    if (widget.existingLeave != null) {
      _initializeForEdit();
    }
  }

  Future<void> _fetchUserLeaveBalance() async {
    try {
      final balance = await Provider.of<AttendanceService>(context, listen: false).getUserLeaveBalance();
      if (mounted) {
        print('[DEBUG] User balance fetched: $balance');
        setState(() {
          _userLeaveBalance = balance;
        });
      }
    } catch (e) {
      if (mounted) {
        print('Failed to load user leave balance: $e');
      }
    }
  }

  void _initializeForEdit() {
    final leave = widget.existingLeave!;
    _leaveType = leave['title'];
    _reasonController.text = leave['subtitle'] ?? '';
    
    // Parse dates (assuming 'days' or direct date strings)
    // The list items from getMyLeaves have 'start' and 'end' as yyyy-MM-dd strings
    try {
      _startDate = DateTime.parse(leave['start']);
      _endDate = DateTime.parse(leave['end']);
    } catch (e) {
      print('Error parsing dates for edit: $e');
    }
  }

  Future<void> _fetchLeaveTypes() async {
    try {
      final types = await Provider.of<AttendanceService>(context, listen: false).getLeaveTypesForUser();
      if (mounted) {
        setState(() {
          _leaveTypes = types;
          _fetchingTypes = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _fetchingTypes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load leave types: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingLeave != null ? 'Edit Leave' : 'Apply Leave'),
        backgroundColor: const Color(0xFF2E5090),
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
      body: _fetchingTypes 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: _leaveType,
                decoration: const InputDecoration(
                  labelText: 'Leave Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: _leaveTypes.map((type) {
                  return DropdownMenuItem<String>(
                    value: type['name'], 
                    child: Text(type['name']),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _leaveType = val;
                    // Get allowed days for selected leave type
                    if (val != null) {
                      final selectedType = _leaveTypes.firstWhere(
                        (type) => type['name'] == val,
                        orElse: () => null,
                      );
                      _selectedLeaveAllowedDays = selectedType?['days_allowed'] ?? 0;
                      
                      // Get balance for selected leave type
                      print('[DEBUG] Selected leave type: $val');
                      print('[DEBUG] Available balance map: $_userLeaveBalance');
                      _selectedLeaveBalance = _userLeaveBalance[val] ?? 0;
                      print('[DEBUG] Balance for $val: $_selectedLeaveBalance');
                    }
                  });
                },
                 validator: (value) => value == null ? 'Please select a leave type' : null,
              ),
              if (_leaveType != null && _selectedLeaveBalance != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      border: Border.all(color: const Color(0xFFFBC02D)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Balance Available:',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF666666),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '$_selectedLeaveBalance day(s)',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFFF57F17),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _selectDateRange,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Select Leave Period',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_month),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _startDate != null && _endDate != null
                            ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year} - ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                            : 'Select date range',
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (_startDate != null && _endDate != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Total: ${_calculateLeaveDays(_startDate!, _endDate!)} day(s) (Sundays excluded)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF2E5090),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_selectedLeaveAllowedDays != null && _selectedLeaveAllowedDays! > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Text(
                                    'Allowed: $_selectedLeaveAllowedDays day(s)',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF666666),
                                    ),
                                  ),
                                ),
                              if (_selectedLeaveAllowedDays != null && _calculateLeaveDays(_startDate!, _endDate!) > _selectedLeaveAllowedDays! && !(_leaveType?.toLowerCase().contains('loss of pay') ?? false))
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEEBEE),
                                      border: Border.all(color: const Color(0xFFC1272D)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '⚠️ Selected days (${_calculateLeaveDays(_startDate!, _endDate!)}) exceed allowed limit ($_selectedLeaveAllowedDays days). Please reduce the date range.',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFFC1272D),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_hasOverlappingLeave && _overlapMessage != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEEBEE),
                                      border: Border.all(color: const Color(0xFFC1272D)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      _overlapMessage!,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFFC1272D),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
                validator: (value) => value == null || value.isEmpty ? 'Please enter a reason' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (_isLoading || _isExceedingLimit() || _hasOverlappingLeave) ? null : _submitLeave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E5090),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(widget.existingLeave != null ? 'Update Application' : 'Submit Application'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF2E5090),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      // Check for overlapping leaves immediately
      _checkForOverlappingLeaves();
    }
  }

  Future<void> _checkForOverlappingLeaves() async {
    if (_startDate == null || _endDate == null) {
      setState(() {
        _hasOverlappingLeave = false;
        _overlapMessage = null;
      });
      return;
    }

    try {
      final myLeaves = await Provider.of<AttendanceService>(context, listen: false).getMyLeaves();
      
      bool hasOverlap = false;
      String? overlapMsg;

      for (var leave in myLeaves) {
        // Skip rejected leaves
        if (leave['status'] == 'Rejected') continue;
        
        try {
          final leaveStart = DateTime.parse(leave['start']);
          final leaveEnd = DateTime.parse(leave['end']);

          // Check if date ranges overlap
          if (!(_endDate!.isBefore(leaveStart) || _startDate!.isAfter(leaveEnd))) {
            hasOverlap = true;
            overlapMsg = '⚠️ Overlapping leave found: ${leave['title']} from ${leaveStart.day}/${leaveStart.month}/${leaveStart.year} to ${leaveEnd.day}/${leaveEnd.month}/${leaveEnd.year}';
            break;
          }
        } catch (e) {
          // Skip if date parsing fails
          continue;
        }
      }

      if (mounted) {
        setState(() {
          _hasOverlappingLeave = hasOverlap;
          _overlapMessage = overlapMsg;
        });
      }
    } catch (e) {
      // Silently fail - don't block UI if overlap check fails
      print('Error checking for overlapping leaves: $e');
    }
  }

  bool _isExceedingLimit() {
    if (_startDate == null || _endDate == null || _selectedLeaveAllowedDays == null) {
      return false;
    }
    // Skip validation for "Loss of Pay" - it can be any number of days
    if (_leaveType?.toLowerCase().contains('loss of pay') ?? false) {
      return false;
    }
    final selectedDays = _calculateLeaveDays(_startDate!, _endDate!);
    return selectedDays > _selectedLeaveAllowedDays!;
  }

  Future<void> _submitLeave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select dates')),
      );
      return;
    }
    if (_isExceedingLimit()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot submit: Selected days (${_calculateLeaveDays(_startDate!, _endDate!)}) exceed allowed limit ($_selectedLeaveAllowedDays days)',
          ),
          backgroundColor: const Color(0xFFC1272D),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (widget.existingLeave != null) {
        await Provider.of<AttendanceService>(context, listen: false).updateLeave(
          widget.existingLeave!['id'],
          _leaveType!,
          _startDate!,
          _endDate!,
          _reasonController.text,
        );
      } else {
        await Provider.of<AttendanceService>(context, listen: false).applyLeave(
          _leaveType!,
          _startDate!,
          _endDate!,
          _reasonController.text,
        );
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.existingLeave != null ? 'Leave updated successfully!' : 'Leave applied successfully!')),
        );
        // Clear form
        _reasonController.clear();
        setState(() {
          _startDate = null;
          _endDate = null;
          _leaveType = null;
        });
        // Notify parent
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
