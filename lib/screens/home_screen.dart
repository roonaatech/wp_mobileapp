import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/attendance_service.dart';
import '../utils/dialogs.dart';
import 'apply_leave_screen.dart';
import 'on_duty_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final GlobalKey<_LeaveDashboardState> _dashboardKey = GlobalKey();

  void _onTabTapped(int index) {
    if (index == 0 && _currentIndex == 0) {
      // If tapping Home while on Home, refresh
      _dashboardKey.currentState?._loadLeaves();
    } else {
      setState(() {
        _currentIndex = index;
      });
      // If coming back to home, maybe refresh? 
      // IndexedStack keeps state, so we might want to refresh explicitly if we want fresh data every time we visit Home.
      if (index == 0) {
         _dashboardKey.currentState?._loadLeaves();
      }
    }
  }

  void _goToHomeAndRefresh() {
    setState(() => _currentIndex = 0);
    _dashboardKey.currentState?._loadLeaves();
  }

  void _handleEdit(Map<String, dynamic> item) {
    bool isLeave = item['type'] == 'leave';
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => isLeave
            ? ApplyLeaveScreen(existingLeave: item, onSuccess: () {
                Navigator.pop(ctx);
                _dashboardKey.currentState?._loadLeaves();
              })
            : OnDutyScreen(existingLog: item, onVisitEnded: () {
                 Navigator.pop(ctx);
                _dashboardKey.currentState?._loadLeaves();
            }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            LeaveDashboard(key: _dashboardKey),
            ApplyLeaveScreen(onSuccess: _goToHomeAndRefresh),
            OnDutyScreen(onVisitEnded: _goToHomeAndRefresh),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                icon: Icons.home_rounded, 
                label: 'Home', 
                index: 0,
              ),
              _buildNavItem(
                icon: Icons.calendar_month_outlined, 
                label: 'Apply Leave', 
                index: 1,
              ),
              _buildNavItem(
                icon: Icons.business_center_outlined, 
                label: 'On-Duty', 
                index: 2,
              ),
            ],
          ),
        ),
      );
  }

  Widget _buildNavItem({
    required IconData icon, 
    required String label, 
    required int index,
  }) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? const Color(0xFF3B82F6) : Colors.grey[600];
    
    return InkWell(
      onTap: () => _onTabTapped(index),
      borderRadius: BorderRadius.circular(50),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color, 
                fontSize: 12, 
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LeaveDashboard extends StatefulWidget {
  const LeaveDashboard({super.key});

  @override
  State<LeaveDashboard> createState() => _LeaveDashboardState();
}

class _LeaveDashboardState extends State<LeaveDashboard> {
  bool _isLoading = true;
  List<dynamic> _leaves = [];
  String? _selectedFilter;
  List<dynamic> _filteredLeaves = [];
  int _selectedYear = DateTime.now().year;
  Set<int> _availableYears = {};
  final ScrollController _statsScrollController = ScrollController();
  Map<String, dynamic> _stats = {
    'totalLeaves': 0,
    'pendingLeaves': 0,
    'approvedLeaves': 0,
    'rejectedLeaves': 0,
    'activeOnDuty': 0,
    'onDutyLeaves': 0
  };

  @override
  void initState() {
    super.initState();
    _loadLeaves();
  }

  @override
  void dispose() {
    _statsScrollController.dispose();
    super.dispose();
  }

  void _scrollStatsLeft() {
    _statsScrollController.animateTo(
      _statsScrollController.offset - 150,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _scrollStatsRight() {
    _statsScrollController.animateTo(
      _statsScrollController.offset + 150,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadLeaves() async {
    // Check if mounted before setting state
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final service = Provider.of<AttendanceService>(context, listen: false);
      final leaves = await service.getMyLeaves();
      final stats = await service.getDashboardStats();
      
      if (mounted) {
        // Extract available years from leaves data
        Set<int> years = {};
        for (var item in leaves) {
          try {
            DateTime? date;
            if (item['type'] == 'leave') {
              date = DateTime.tryParse(item['start'].toString());
            } else {
              date = DateTime.tryParse(item['start'].toString());
            }
            if (date != null) {
              years.add(date.year);
            }
          } catch (e) {
            // Skip items with invalid dates
          }
        }
        // Always include current year
        years.add(DateTime.now().year);
        
        setState(() {
          _leaves = leaves;
          _stats = stats;
          _availableYears = years;
          _selectedYear = DateTime.now().year;
          // Always default to Pending filter on home page
          _selectedFilter = 'Pending';
          _applyFilterAndYear('Pending', _selectedYear);
        });
      }
    } catch (error) {
      print('[HomeScreen Error] $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter(String? filterName) {
    _applyFilterAndYear(filterName, _selectedYear);
  }

  void _applyFilterAndYear(String? filterName, int year) {
    final filtered = _leaves.where((item) {
      // First filter by year
      try {
        DateTime? date;
        if (item['type'] == 'leave') {
          date = DateTime.tryParse(item['start'].toString());
        } else {
          date = DateTime.tryParse(item['start'].toString());
        }
        if (date == null || date.year != year) {
          return false;
        }
      } catch (e) {
        return false;
      }
      
      // Then apply status/type filter
      if (filterName == null) {
        return true;
      }
      
      switch (filterName) {
        case 'Total Leaves':
          return item['type'] == 'leave';
        case 'Total On-Duty':
          return item['type'] == 'on-duty' || item['type'] == 'on_duty';
        case 'Approved':
          return item['status']?.toLowerCase() == 'approved';
        case 'Rejected':
          return item['status']?.toLowerCase() == 'rejected';
        case 'Pending':
          return item['status']?.toLowerCase() == 'pending';
        case 'Active On-Duty':
          return (item['type'] == 'on-duty' || item['type'] == 'on_duty') && item['end'] == null;
        default:
          return true;
      }
    }).toList();
    
    // Calculate stats for the selected year
    final yearLeaves = _leaves.where((item) {
      try {
        DateTime? date = DateTime.tryParse(item['start'].toString());
        return date != null && date.year == year;
      } catch (e) {
        return false;
      }
    }).toList();

    int totalLeaves = 0;
    int onDutyLeaves = 0;
    int pendingLeaves = 0;
    int approvedLeaves = 0;
    int rejectedLeaves = 0;
    int activeOnDuty = 0;

    for (var item in yearLeaves) {
      final status = item['status']?.toLowerCase() ?? '';
      final type = item['type'];

      if (type == 'leave') {
        totalLeaves++;
        if (status == 'pending') pendingLeaves++;
        if (status == 'approved') approvedLeaves++;
        if (status == 'rejected') rejectedLeaves++;
      } else if (type == 'on-duty' || type == 'on_duty') {
        onDutyLeaves++;
        if (status == 'pending') pendingLeaves++;
        if (status == 'approved') approvedLeaves++;
        if (status == 'rejected') rejectedLeaves++;
        if (item['end'] == null) activeOnDuty++;
      }
    }

    // Update both filtered leaves and stats together
    _filteredLeaves = filtered;
    _stats = {
      'totalLeaves': totalLeaves,
      'pendingLeaves': pendingLeaves,
      'approvedLeaves': approvedLeaves,
      'rejectedLeaves': rejectedLeaves,
      'activeOnDuty': activeOnDuty,
      'onDutyLeaves': onDutyLeaves
    };
  }

  List<dynamic> _getUpcomingLeaves() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final ninetyDaysFromNow = today.add(const Duration(days: 90));
    
    return _leaves.where((item) {
      if (item['type'] != 'leave') return false;
      try {
        final startDate = DateTime.tryParse(item['start'].toString());
        if (startDate == null) return false;
        return (startDate.isAtSameMomentAs(today) || startDate.isAfter(today)) && 
               startDate.isBefore(ninetyDaysFromNow);
      } catch (e) {
        return false;
      }
    }).toList()..sort((a, b) {
       final dateA = DateTime.tryParse(a['start'].toString()) ?? DateTime(2099, 12, 31);
       final dateB = DateTime.tryParse(b['start'].toString()) ?? DateTime(2099, 12, 31);
       return dateA.compareTo(dateB);
    });
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return const Color(0xFF4CAF50);
      case 'rejected': return const Color(0xFFC1272D);
      case 'pending': return const Color(0xFFFFA000);
      case 'active': return const Color(0xFF8FA3D1);
      case 'completed': return Colors.grey;
      default: return const Color(0xFFC1272D);
    }
  }

  Color _getStatusBackgroundColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved': return const Color(0xFFE8F5E9);
      case 'rejected': return const Color(0xFFFFEBEE);
      case 'pending': return const Color(0xFFFFF8E1);
      case 'active': return const Color(0xFFE3F2FD);
      case 'completed': return const Color(0xFFF5F5F5);
      default: return Colors.grey[50]!;
    }
  }

  String _formatDateRange(dynamic item) {
    final isLeave = item['type'] == 'leave';
    
    if (isLeave) {
      return '${item['start']}  -  ${item['end']}';
    } else {
      final start = DateTime.parse(item['start'].toString()).toLocal();
      final end = item['end'] != null ? DateTime.parse(item['end'].toString()).toLocal() : null;
      String dateRange = '${start.day}/${start.month} ${start.hour}:${start.minute.toString().padLeft(2,'0')}';
      if (end != null) {
        dateRange += ' - ${end.hour}:${end.minute.toString().padLeft(2,'0')}';
      } else {
        dateRange += ' (Active)';
      }
      return dateRange;
    }
  }

  Widget _buildStatCard(String label, String count, Color color) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
          _applyFilterAndYear(label, _selectedYear);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.3),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(count, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteRequest(int id, {bool isOnDuty = false}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Are you sure you want to delete this request? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final service = Provider.of<AttendanceService>(context, listen: false);
        await service.deleteLeaveOrOnDuty(id, isOnDuty: isOnDuty);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request deleted successfully!')),
        );
        
        _loadLeaves();
      } catch (error) {
        showErrorDialog(context, 'Failed to delete request: $error');
      }
    }
  }

  void _showDetailsModal(Map<String, dynamic> item, bool isLeave, String dateRange) {
    final status = item['status'];
    final statusColor = _getStatusColor(status);
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Title and Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      isLeave ? item['title'] : 'On-Duty: ${item['title'].toString().replaceAll('On-Duty: ', '')}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF3B82F6),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Request ID
              if (item['id'] != null) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.tag, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        'Request ID: ${item['id']}',
                        style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Date Range
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      dateRange,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Days/Hours (if leave)
              if (isLeave && item['days_requested'] != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 10),
                          Text(
                            'Duration: ${item['days_requested']} day(s)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Requester Info
              if (item['requester'] != null) ...[
                Text(
                  'Requester Information',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['requester']['firstname']} ${item['requester']['lastname']}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (item['requester']['email'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          item['requester']['email'],
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                      if (item['requester']['department'] != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Dept: ${item['requester']['department']}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Manager Info
              if (item['manager'] != null) ...[
                Text(
                  'Manager',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${item['manager']['firstname']} ${item['manager']['lastname']}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Subtitle/Location
              if (item['subtitle'] != null) ...[
                Text(
                  'Details',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item['subtitle'],
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
                const SizedBox(height: 16),
              ],
              
              // Reason/Notes
              if (item['reason'] != null && item['reason'].toString().isNotEmpty) ...[
                Text(
                  'Reason',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    item['reason'],
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Comments/Notes
              if (item['comment'] != null && item['comment'].toString().isNotEmpty) ...[
                Text(
                  'Notes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Text(
                    item['comment'],
                    style: TextStyle(color: Colors.grey[700], fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Rejection Reason
              if (item['rejection_reason'] != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rejection Reason',
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['rejection_reason'],
                              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Approver Info
              if (item['approver'] != null && status != 'Pending') ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: status == 'Rejected' ? Colors.red.shade50 : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: status == 'Rejected' ? Colors.red.shade300 : Colors.green.shade300,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        status == 'Rejected' ? Icons.cancel : Icons.check_circle,
                        size: 16,
                        color: status == 'Rejected' ? Colors.red.shade700 : Colors.green.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${status == 'Rejected' ? 'Rejected' : 'Approved'} by',
                              style: TextStyle(
                                color: status == 'Rejected' ? Colors.red.shade700 : Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${item['approver']['firstname']} ${item['approver']['lastname']}',
                              style: TextStyle(
                                color: status == 'Rejected' ? Colors.red.shade700 : Colors.green.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Timestamps
              if (item['createdAt'] != null || item['updatedAt'] != null) ...[
                Text(
                  'Activity Timeline',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item['createdAt'] != null) ...[
                        Row(
                          children: [
                            Icon(Icons.add_circle_outline, size: 14, color: Colors.blue[600]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Created',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                                  ),
                                  Text(
                                    '${item['createdAt']}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (item['createdAt'] != null && (item['updatedAt'] != null || status != 'Pending')) ...[
                        const SizedBox(height: 10),
                      ],
                      if (item['updatedAt'] != null && item['updatedAt'] != item['createdAt']) ...[
                        Row(
                          children: [
                            Icon(Icons.update, size: 14, color: Colors.orange[600]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Last Updated',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                                  ),
                                  Text(
                                    '${item['updatedAt']}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (status != 'Pending' && item['approver'] != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              status == 'Rejected' ? Icons.cancel : Icons.check_circle_outline,
                              size: 14,
                              color: status == 'Rejected' ? Colors.red[600] : Colors.green[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    status == 'Rejected' ? 'Rejected' : 'Approved',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    'By ${item['approver']['firstname']} ${item['approver']['lastname']}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Close Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Welcome,', style: TextStyle(color: Colors.white70, fontSize: 14)),
                      Text(
                        authService.userName ?? 'User', 
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white),
                    onPressed: () => authService.logout(),
                  )
                ],
              ),
            ],
          ),
        ),

        // Year Selector - Enhanced Design
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.grey[50]!, Colors.grey[100]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 14, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 6),
                    const Text(
                      'Year',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8FA3D1).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _selectedYear.toString(),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF3B82F6),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      ..._availableYears.toList()..sort((a, b) => b.compareTo(a)),
                    ].map((year) {
                      final isSelected = _selectedYear == year;
                      final isCurrentYear = year == DateTime.now().year;
                      
                      return Padding(
                        padding: const EdgeInsets.only(right: 4.0),
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedYear = year;
                              _applyFilterAndYear(_selectedFilter, year);
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : LinearGradient(
                                      colors: [Colors.white, Colors.grey[50]!],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected ? Colors.transparent : Colors.grey[300]!,
                                width: 1,
                              ),
                              boxShadow: [
                                if (isSelected)
                                  BoxShadow(
                                    color: const Color(0xFF8FA3D1).withOpacity(0.2),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  )
                                else
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.03),
                                    blurRadius: 2,
                                    offset: const Offset(0, 0.5),
                                  ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  year.toString(),
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.grey[800],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 9,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                if (isCurrentYear)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 1.0),
                                    child: Text(
                                      'Now',
                                      style: TextStyle(
                                        color: isSelected ? Colors.white70 : Colors.grey[600],
                                        fontSize: 6,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),

        // List
        Expanded(
          child: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _filteredLeaves.isEmpty
              ? _buildEmptyStateWithUpcoming()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredLeaves.length,
                  itemBuilder: (context, index) => _buildLeaveItem(_filteredLeaves[index]),
                ),
        ),

        // Stats Grid (Bottom) - Single Row layout with scroll indicators
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12.0),
          child: Row(
            children: [
              // Left Arrow
              GestureDetector(
                onTap: _scrollStatsLeft,
                child: Container(
                  width: 30,
                  height: 60,
                  alignment: Alignment.center,
                  child: const Icon(Icons.chevron_left, color: Color(0xFF3B82F6), size: 24),
                ),
              ),
              // Scrollable Cards
              Expanded(
                child: SingleChildScrollView(
                  controller: _statsScrollController,
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: _buildStatCard('Total Leaves', (_stats['totalLeaves'] ?? 0).toString(), Colors.purple),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 120,
                        child: _buildStatCard('Total On-Duty', (_stats['onDutyLeaves'] ?? 0).toString(), Colors.blue),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 120,
                        child: _buildStatCard('Approved', (_stats['approvedLeaves'] ?? 0).toString(), Colors.green),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 120,
                        child: _buildStatCard('Rejected', (_stats['rejectedLeaves'] ?? 0).toString(), Colors.red),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 120,
                        child: _buildStatCard('Pending', (_stats['pendingLeaves'] ?? 0).toString(), Colors.orange),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 120,
                        child: _buildStatCard('Active On-Duty', (_stats['activeOnDuty'] ?? 0).toString(), Colors.cyan),
                      ),
                    ],
                  ),
                ),
              ),
              // Right Arrow
              GestureDetector(
                onTap: _scrollStatsRight,
                child: Container(
                  width: 30,
                  height: 60,
                  alignment: Alignment.center,
                  child: const Icon(Icons.chevron_right, color: Color(0xFF3B82F6), size: 24),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyStateWithUpcoming() {
    final upcoming = _getUpcomingLeaves();
    
    if (upcoming.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              _selectedFilter == null ? 'No leave history found' : 'No items found for this filter',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              _selectedFilter == null ? 'No leave history found' : 'No items found for this filter',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.event, size: 18, color: Color(0xFF3B82F6)),
              SizedBox(width: 8),
              Text(
                'Upcoming Leaves (Next 90 Days)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3B82F6),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: upcoming.length,
            itemBuilder: (context, index) => _buildLeaveItem(upcoming[index]),
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveItem(Map<String, dynamic> item) {
    final isLeave = item['type'] == 'leave';
    final dateRange = _formatDateRange(item);

    return GestureDetector(
      onTap: () => _showDetailsModal(item, isLeave, dateRange),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              Colors.grey[50]!,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _getStatusColor(item['status']).withOpacity(0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _getStatusColor(item['status']).withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          isLeave ? const Color(0xFF3B82F6) : const Color(0xFFC1272D),
                          isLeave ? const Color(0xFF8B5CF6) : const Color(0xFFD63A44),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: (isLeave ? const Color(0xFF3B82F6) : const Color(0xFFC1272D)).withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      isLeave ? item['title'] : 'On-Duty',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(item['status']).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _getStatusColor(item['status']).withOpacity(0.4),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      item['status'],
                      style: TextStyle(
                        color: _getStatusColor(item['status']),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isLeave) ...[
                          Text(
                            item['title'].toString().replaceAll('On-Duty: ', ''),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Colors.grey[900],
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.calendar_today,
                                size: 13,
                                color: Colors.blue[700],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              dateRange,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                                color: Colors.grey[700],
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (item['status']?.toLowerCase() == 'pending') ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blue[50]!, Colors.blue[100]!],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: IconButton(
                          icon: Icon(Icons.edit, color: Colors.blue[700], size: 16),
                          onPressed: () => (context.findAncestorStateOfType<_HomeScreenState>()?._handleEdit(item)),
                          tooltip: 'Edit',
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.red[50]!, Colors.red[100]!],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: IconButton(
                          icon: Icon(Icons.delete, color: Colors.red[700], size: 16),
                          onPressed: () {
                            try {
                              int id;
                              if (item['id'] is int) {
                                id = item['id'];
                              } else {
                                id = int.parse(item['id'].toString().trim());
                              }
                              final itemType = item['type']?.toString() ?? '';
                              final isOnDuty = itemType == 'on-duty' || itemType == 'on_duty';
                              _deleteRequest(id, isOnDuty: isOnDuty);
                            } catch (e) {
                              showErrorDialog(context, 'Error: Invalid request ID format');
                            }
                          },
                          tooltip: 'Delete',
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

