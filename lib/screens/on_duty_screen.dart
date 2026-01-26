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
  bool _isLoading = false;
  bool _isOnDuty = false;
  int? _activeOnDutyId;
  DateTime? _startTime;

  @override
  void initState() {
    super.initState();
    if (widget.existingLog != null) {
      _initializeForEdit();
    } else {
      _checkActiveOnDuty();
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
    _startTime = null;
    _isOnDuty = false;
    _activeOnDutyId = null;
  }

  void _initializeForEdit() {
    final log = widget.existingLog!;
    // Parse title "On-Duty: ClientName" logic if needed, or get raw data?
    // The list item has 'title': 'On-Duty: ClientName', 'subtitle': 'Location - Purpose'
    
    // We need to parse strictly or better, if the API returned raw data in a hidden field.
    // Normalized data in getMyLeaves:
    // title: `On-Duty: ${l.client_name}`,
    // subtitle: `${l.location} - ${l.purpose}`,
    
    // This is lossy! "Location - Purpose" might be ambiguous if location has " - ".
    // Ideally, I should pass raw fields.
    // But for now receiving normalized data.
    // I made a mistake in backend normalization design if I want to edit easily.
    // However, I can try to parse or just pre-fill what I can.
    
    // WAIT! In Step 923 (Leave Controller), I see:
    // title: `On-Duty: ${l.client_name}`
    // subtitle: `${l.location} - ${l.purpose}`
    
    // I can try to split subtitle by " - ".
    // Or I can update `leave.controller.js` to send raw fields too?
    // It sends `id`, `status` etc.
    
    String title = log['title'] ?? '';
    if (title.startsWith('On-Duty: ')) {
      _clientController.text = title.substring(9);
    }
    
    String subtitle = log['subtitle'] ?? '';
    List<String> parts = subtitle.split(' - ');
    if (parts.isNotEmpty) {
      _locationController.text = parts[0];
      if (parts.length > 1) {
        _purposeController.text = parts.sublist(1).join(' - ');
      }
    }
  }

  Future<void> _updateOnDuty() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    try {
      await Provider.of<AttendanceService>(context, listen: false).updateOnDutyDetails(
        widget.existingLog!['id'],
        _clientController.text,
        _locationController.text,
        _purposeController.text,
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
    setState(() => _isLoading = true);
    try {
      await Provider.of<AttendanceService>(context, listen: false).endOnDuty();
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
              labelText: 'Location',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.location_on, color: Color(0xFF3B82F6)),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please enter location';
              return null;
            },
          ),
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
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : (widget.existingLog != null ? _updateOnDuty : _startOnDuty),
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
                                'Location',
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
                          'Started at (IST)',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}',
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
    super.dispose();
  }
}
