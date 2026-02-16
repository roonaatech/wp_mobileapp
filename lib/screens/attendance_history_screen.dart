import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/attendance_service.dart';
import '../utils/ist_helper.dart';
import '../utils/dialogs.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final String title;
  final String type; // 'checkins', 'checkouts', 'onduty', 'inprogress', 'onduty_active'
  
  const AttendanceHistoryScreen({
    super.key,
    required this.title,
    required this.type,
  });

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  bool _isLoading = true;
  int? _processingItemId;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final service = Provider.of<AttendanceService>(context, listen: false);
      final result = await service.getAttendanceHistory(widget.type);
      print('History type: ${widget.type}');
      print('Items received: ${result['items']?.length ?? 0}');
      if (result['items'] != null && result['items'].isNotEmpty) {
        print('First item: ${result['items'][0]}');
      }
      setState(() {
        _items = result['items'] ?? [];
      });
    } catch (error) {
      print('Error loading history: $error');
      showErrorDialog(context, 'Failed to load history: $error');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _calculateDuration(Map<String, dynamic> item, bool isOnDuty, bool isInProgress) {
    DateTime startTime;
    DateTime? endTime;

                            if (isOnDuty) ...[
                              Text(
                                'Client: ${item['client_name'] ?? 'N/A'}',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Location: ${item['location_details'] ?? item['location'] ?? 'N/A'}',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Purpose: ${item['purpose'] ?? 'N/A'}',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                            ],
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '$hours hr ${minutes} min';
    } else {
      return '$minutes min';
    }
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('d/M/yyyy h:mm a').format(dt);
  }

  String _getApprovalStatus(Map<String, dynamic> item) {
    // Check for approval_status field
    if (item.containsKey('approval_status')) {
      return item['approval_status'] ?? 'Pending';
    }
    return 'Pending';
  }

  Color _getApprovalStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  IconData _getApprovalStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Icons.check_circle;
      case 'rejected':
        return Icons.cancel;
      case 'pending':
      default:
        return Icons.schedule;
    }
  }

  Future<void> _completeOnDuty(int id) async {
    setState(() => _processingItemId = id);
    try {
      final service = Provider.of<AttendanceService>(context, listen: false);
      await service.endOnDuty();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('On-duty visit completed!')),
      );
      
      _loadHistory();
    } catch (error) {
      showErrorDialog(context, 'Failed to complete on-duty: $error');
      setState(() => _processingItemId = null);
    }
  }

  Future<void> _deleteRequest(int id) async {
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
      setState(() => _processingItemId = id);
      try {
        final service = Provider.of<AttendanceService>(context, listen: false);
        await service.deleteLeaveOrOnDuty(id);
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request deleted successfully!')),
        );
        
        _loadHistory();
      } catch (error) {
        showErrorDialog(context, 'Failed to delete request: $error');
      } finally {
        if (mounted) {
          setState(() => _processingItemId = null);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Gradient Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? const Center(
                        child: Text(
                          'No records found',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final isOnDuty = item.containsKey('client_name');
                          final isInProgress = isOnDuty 
                              ? item['end_time'] == null 
                              : item['check_out_time'] == null;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isOnDuty ? Icons.work : Icons.login,
                                  color: isOnDuty
                                      ? Color(0xFF3B82F6) // blue for On-duty
                                      : (isInProgress ? Colors.green : Colors.grey),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                if (isOnDuty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Color(0xFF3B82F6), // blue background
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'On-Duty',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                if (isOnDuty) const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    isOnDuty
                                        ? (item['client_name'] ?? 'On-Duty Visit')
                                        : 'Check-in',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isOnDuty ? Color(0xFF3B82F6) : null,
                                    ),
                                  ),
                                ),
                                // Approval status badge
                                if (!isInProgress) ...[
                                  const SizedBox(width: 8),
                                  Chip(
                                    label: Text(
                                      _getApprovalStatus(item),
                                      style: const TextStyle(fontSize: 11, color: Colors.white),
                                    ),
                                    backgroundColor: _getApprovalStatusColor(_getApprovalStatus(item)),
                                    padding: EdgeInsets.zero,
                                    avatar: Icon(
                                      _getApprovalStatusIcon(_getApprovalStatus(item)),
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                                if (isInProgress)
                                  Chip(
                                    label: const Text(
                                      'Active',
                                      style: TextStyle(fontSize: 11, color: Colors.white),
                                    ),
                                    backgroundColor: Colors.green,
                                    padding: EdgeInsets.zero,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (isOnDuty) ...[
                              Text(
                                'Location: ${item['location_details'] ?? item['location'] ?? 'N/A'}',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Purpose: ${item['purpose'] ?? 'N/A'}',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                            ],
                            Row(
                              children: [
                                Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 4),
                                Text(
                                  isOnDuty
                                      ? 'Start: ${_formatDateTime(ISTHelper.parseUTCtoIST(item['start_time']))}'
                                      : 'In: ${_formatDateTime(ISTHelper.parseUTCtoIST(item['check_in_time']))}',
                                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                ),
                              ],
                            ),
                            if (!isInProgress) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.logout, size: 14, color: Colors.grey.shade600),
                                  const SizedBox(width: 4),
                                  Text(
                                    isOnDuty
                                        ? 'End: ${_formatDateTime(ISTHelper.parseUTCtoIST(item['end_time']))}'
                                        : 'Out: ${_formatDateTime(ISTHelper.parseUTCtoIST(item['check_out_time']))}',
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            // Duration display
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.timer, size: 14, color: Colors.blue.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Duration: ${_calculateDuration(item, isOnDuty, isInProgress)}',
                                    style: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Approver information
                            if (!isInProgress && item['approver'] != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.purple.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, size: 14, color: Colors.purple.shade700),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Approved by: ${item['approver']['firstname']} ${item['approver']['lastname']}',
                                        style: TextStyle(
                                          color: Colors.purple.shade700,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            // Action buttons for in-progress items
                            if (isInProgress && isOnDuty) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: (_processingItemId != null) ? null : () => _completeOnDuty(item['id']),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                  icon: (_processingItemId == item['id'])
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : Icon(isOnDuty ? Icons.check_circle : Icons.logout, size: 18),
                                  label: Text(isOnDuty ? 'Complete On-Duty' : 'Check Out'),
                               ),
                             ),
                           ],
                           // Edit and Delete buttons for pending requests
                           if (item['status']?.toLowerCase() == 'pending')
                             Row(
                               mainAxisSize: MainAxisSize.min,
                               children: [
                                 IconButton(
                                   icon: const Icon(Icons.edit, color: Colors.blue),
                                   onPressed: () => _deleteRequest(item['id']),
                                 ),
                                 IconButton(
                                   icon: const Icon(Icons.delete, color: Colors.red),
                                   onPressed: () => _deleteRequest(item['id']),
                                 ),
                               ],
                             ),
                         ],
                       ),
                     ),
                   );
                 },
               ),
          ),
        ],
      ),
    );
  }
}
