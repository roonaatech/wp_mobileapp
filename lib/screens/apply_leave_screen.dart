import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../services/attendance_service.dart';
import '../utils/dialogs.dart';

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
  Map<DateTime, String> _existingLeavesStatus = {};
  bool _hasLoadedData = false;

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
    if (widget.existingLeave != null) {
      _initializeForEdit();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Always fetch fresh data from database when screen appears
    if (!_hasLoadedData) {
      print('[ApplyLeave] Loading fresh data from database...');
      _loadAllData();
      _hasLoadedData = true;
    }
  }

  // Method to load all data from database
  Future<void> _loadAllData() async {
    print('[ApplyLeave] Fetching leave types, balance, and existing leaves...');
    await Future.wait([
      _fetchLeaveTypes(),
      _fetchUserLeaveBalance(),
      _fetchMyLeaves(),
    ]);
    print('[ApplyLeave] Data loaded. Leave types count: ${_leaveTypes.length}');
  }

  Future<void> _fetchMyLeaves() async {
    try {
      final leaves = await Provider.of<AttendanceService>(context, listen: false).getMyLeaves();
      if (mounted) {
        final Map<DateTime, String> statusMap = {};
        for (var leave in leaves) {
          // Skip rejected leaves if you don't want to show them, or show them in red? 
          // User asked for "pending and approved".
          if (leave['status'] == 'Rejected') continue;

          try {
            // Ensure we handle dates as local to match calendar logic
            final rawStart = DateTime.parse(leave['start']);
            final rawEnd = DateTime.parse(leave['end']);
            
            final start = rawStart.isUtc ? rawStart.toLocal() : rawStart;
            final end = rawEnd.isUtc ? rawEnd.toLocal() : rawEnd;
            
            final status = leave['status'];

            // Loop through dates
            DateTime current = start;
            while (!current.isAfter(end)) {
              // Normalize date (remove time, ensure local)
              final dateKey = DateTime(current.year, current.month, current.day);
              statusMap[dateKey] = status;
              current = current.add(const Duration(days: 1));
            }
          } catch (e) {
            print('Error parsing leave date: $e');
          }
        }
        setState(() {
          _existingLeavesStatus = statusMap;
        });
      }
    } catch (e) {
      print('Failed to fetch existing leaves: $e');
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
      print('[ApplyLeave] Calling API to get leave types...');
      final types = await Provider.of<AttendanceService>(context, listen: false).getLeaveTypesForUser();
      print('[ApplyLeave] Received ${types.length} leave types from API');
      if (types.isNotEmpty) {
        print('[ApplyLeave] First leave type: ${types[0]}');
      }
      if (mounted) {
        setState(() {
          _leaveTypes = types;
          _fetchingTypes = false;
        });
      }
    } catch (e) {
      print('[ApplyLeave] Error fetching leave types: $e');
      if (mounted) {
        setState(() => _fetchingTypes = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load leave types: $e')),
        );
      }
    }
  }

  void _showLeaveTypeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Leave Type'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _leaveTypes.length,
            itemBuilder: (context, index) {
              final type = _leaveTypes[index];
              final isSelected = _leaveType == type['name'];
              return ListTile(
                title: Text(type['name']),
                selected: isSelected,
                selectedTileColor: const Color(0xFF3B82F6).withOpacity(0.2),
                onTap: () {
                  setState(() {
                    _leaveType = type['name'];
                    _selectedLeaveAllowedDays = type['days_allowed'] ?? 0;
                    _selectedLeaveBalance = _userLeaveBalance[type['name']] ?? 0;
                    print('[DEBUG] Selected leave type: ${type['name']}');
                    print('[DEBUG] Balance: $_selectedLeaveBalance');
                  });
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingLeave != null ? 'Edit Leave' : 'Apply Leave'),
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
      body: _fetchingTypes 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                readOnly: true,
                controller: TextEditingController(text: _leaveType ?? ''),
                decoration: const InputDecoration(
                  labelText: 'Leave Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
                onTap: () async {
                  print('[ApplyLeave] Leave Type field tapped - refreshing from DB');
                  await _fetchLeaveTypes();
                  if (mounted) {
                    _showLeaveTypeDialog();
                  }
                },
                validator: (value) => value?.isEmpty ?? true ? 'Please select a leave type' : null,
              ),
              // Balance Available display disabled
              // if (_leaveType != null && _selectedLeaveBalance != null)
              //   Padding(
              //     padding: const EdgeInsets.only(top: 8.0),
              //     child: Container(
              //       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              //       decoration: BoxDecoration(
              //         color: const Color(0xFFFFF8E1),
              //         border: Border.all(color: const Color(0xFFFBC02D)),
              //         borderRadius: BorderRadius.circular(4),
              //       ),
              //       child: Row(
              //         mainAxisAlignment: MainAxisAlignment.spaceBetween,
              //         children: [
              //           Text(
              //             'Balance Available:',
              //             style: const TextStyle(
              //               fontSize: 11,
              //               color: Color(0xFF666666),
              //               fontWeight: FontWeight.w500,
              //             ),
              //           ),
              //           Text(
              //             '$_selectedLeaveBalance day(s)',
              //             style: const TextStyle(
              //               fontSize: 13,
              //               color: Color(0xFFF57F17),
              //               fontWeight: FontWeight.bold,
              //             ),
              //           ),
              //         ],
              //       ),
              //     ),
              //   ),
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
                                  color: Color(0xFF3B82F6),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              // Removed "Allowed: xx days" display
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
                                      '⚠️ Your leave request exceeds the available balance. Please contact your manager to discuss this leave request.',
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
                  backgroundColor: const Color(0xFF3B82F6),
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
    // Refresh pending and approved leaves from database when calendar opens
    print('[ApplyLeave] Calendar opened - refreshing leaves from DB');
    await _fetchMyLeaves();
    
    // Debug prints
    print('Opening calendar. Existing leaves status map: ${_existingLeavesStatus.length} entries');
    _existingLeavesStatus.forEach((k, v) => print('Date: $k, Status: $v'));

    // Custom calendar picker with highligting
    DateTime? tempStart = _startDate;
    DateTime? tempEnd = _endDate;
    DateTime focusedDay = _startDate ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(8),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Select Leave Dates', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          )
                        ],
                      ),
                    ),
                    TableCalendar(
                      firstDay: DateTime.now(),
                      lastDay: DateTime.now().add(const Duration(days: 365)),
                      focusedDay: focusedDay,
                      selectedDayPredicate: (day) => false, // We use range selection
                      rangeStartDay: tempStart,
                      rangeEndDay: tempEnd,
                      calendarFormat: CalendarFormat.month,
                      rangeSelectionMode: RangeSelectionMode.toggledOn,
                      enabledDayPredicate: (day) {
                        // Disable past dates (before today)
                        final today = DateTime.now();
                        final todayOnly = DateTime(today.year, today.month, today.day);
                        final dayOnly = DateTime(day.year, day.month, day.day);
                        return !dayOnly.isBefore(todayOnly);
                      },
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                      ),
                      availableGestures: AvailableGestures.horizontalSwipe,
                      onDaySelected: (selectedDay, focused) {
                         // Switch to range mode logic handled by onRangeSelected usually
                         setModalState(() {
                           focusedDay = focused;
                         });
                      },
                      onRangeSelected: (start, end, focused) {
                        setModalState(() {
                          tempStart = start;
                          tempEnd = end;
                          focusedDay = focused;
                        });
                      },
                      onPageChanged: (focused) {
                        focusedDay = focused;
                      },
                      calendarBuilders: CalendarBuilders(
                        defaultBuilder: (context, day, focusedDay) {
                          // Check if day matches existing leave
                          final dateKey = DateTime(day.year, day.month, day.day);
                          final status = _existingLeavesStatus[dateKey];
                          
                          if (status != null) {
                            Color color = Colors.grey;
                            if (status == 'Approved') color = Colors.green.withOpacity(0.3);
                            if (status == 'Pending') color = Colors.orange.withOpacity(0.3);
                            
                            return Container(
                              margin: const EdgeInsets.all(4),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${day.day}',
                                style: const TextStyle(color: Colors.black87),
                              ),
                            );
                          }
                          return null; // Use default
                        },
                      ),
                    ),
                    // Legend
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildLegendItem('Approved', Colors.green.withOpacity(0.3)),
                        _buildLegendItem('Pending', Colors.orange.withOpacity(0.3)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (tempStart != null) {
                             Navigator.pop(ctx, DateTimeRange(start: tempStart!, end: tempEnd ?? tempStart!));
                          } else {
                            Navigator.pop(ctx);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                           backgroundColor: const Color(0xFF3B82F6),
                           foregroundColor: Colors.white,
                        ),
                        child: const Text('Confirm Selection'),
                      ),
                    ),
                  )
                ],
              );
            }
          ),
        ),
      ),
      ),
    ).then((pickedRange) {
      if (pickedRange is DateTimeRange) {
        setState(() {
          _startDate = pickedRange.start;
          _endDate = pickedRange.end;
        });
        _checkForOverlappingLeaves();
      }
    });
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
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
      showErrorDialog(context, 'Please select dates');
      return;
    }
    if (_isExceedingLimit()) {
      showErrorDialog(context, 'Your leave request exceeds the available balance. Please contact your manager to discuss this leave request.');
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
        
        // Refresh data to show new pending leave and updated balance
        await _fetchMyLeaves();
        await _fetchUserLeaveBalance();

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
        var msg = e.toString();
        msg = msg.replaceFirst(RegExp(r'^Exception:\s*'), '');
        showErrorDialog(context, msg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
