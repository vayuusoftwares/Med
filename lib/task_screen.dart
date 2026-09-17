import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'models/user_model.dart';
import 'app_config.dart';
import 'services/map_url_service.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class _Doctor {
  final int? id;
  final String name;
  final String speciality;
  final String phone;
  final String area;
  final int? addedBy;

  const _Doctor(this.name, this.speciality, [this.phone = '', this.id, this.addedBy, this.area = '']);

  String get uniqueKey => id != null ? 'doc_$id' : 'doc_${name}_${speciality}_$area';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Doctor &&
          runtimeType == other.runtimeType &&
          (id != null && other.id != null
              ? id == other.id
              : name == other.name && speciality == other.speciality && phone == other.phone && area == other.area);

  @override
  int get hashCode => id != null ? id.hashCode : Object.hash(name, speciality, phone, area);
}

class _Clinic {
  final int? id;
  final String name;
  final double lat;
  final double lng;
  final String address;
  final String phone;
  final String area;
  final int? addedBy;

  const _Clinic(this.name, this.lat, this.lng, this.address, [this.phone = '', this.id, this.addedBy, this.area = '']);

  String get uniqueKey => id != null ? 'clin_$id' : 'clin_${name}_${lat}_${lng}_$area';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _Clinic &&
          runtimeType == other.runtimeType &&
          (id != null && other.id != null
              ? id == other.id
              : name == other.name && lat == other.lat && lng == other.lng && address == other.address && area == other.area);

  @override
  int get hashCode => id != null ? id.hashCode : Object.hash(name, lat, lng, address, area);
}

class _DoctorClinicSuggestion {
  final _Doctor doctor;
  final _Clinic clinic;

  const _DoctorClinicSuggestion({
    required this.doctor,
    required this.clinic,
  });

  String get area => clinic.area.isNotEmpty ? clinic.area : doctor.area;
  String get title => '${doctor.name} — ${clinic.name}';
  String get subtitle {
    final parts = <String>[];
    if (area.isNotEmpty) parts.add('AREA: ${area.toUpperCase()}');
    if (doctor.speciality.isNotEmpty) parts.add(doctor.speciality);
    if (clinic.address.isNotEmpty) parts.add(clinic.address);
    return parts.join(' • ');
  }

  String get uniqueKey => '${doctor.uniqueKey}_${clinic.uniqueKey}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DoctorClinicSuggestion &&
          runtimeType == other.runtimeType &&
          doctor == other.doctor &&
          clinic == other.clinic;

  @override
  int get hashCode => Object.hash(doctor, clinic);
}

class _Visit {
  _Doctor? doctor;
  _Clinic? clinic;
  String? taskCategory;
  _Visit();
}

class _DayPlan {
  int dayNumber;
  List<_Visit> visits;

  _DayPlan({required this.dayNumber, List<_Visit>? visits})
      : visits = visits ?? [_Visit()];
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class TaskScreen extends StatefulWidget {
  final User salesRep;
  final double? repLat;
  final double? repLng;
  final Map<String, dynamic>? existingTask;

  const TaskScreen({
    super.key,
    required this.salesRep,
    this.repLat,
    this.repLng,
    this.existingTask,
  });

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen>
    with SingleTickerProviderStateMixin {
  String _taskBasis = 'Daily';
  double? _repLat;
  double? _repLng;
  bool _loadingLoc = false;
  String _locStatus = '';
  List<_Doctor> _doctors = [];
  List<_Clinic> _clinics = [];
  List<_DoctorClinicSuggestion> _combinations = [];
  String _selectedArea = 'All Areas';
  List<String> _areas = ['All Areas', 'Chennai', 'Villupuram', 'Cuddalore', 'Tindivanam'];
  bool _isLoadingData = true;
  final List<String> _taskCategories = [
    'Gifts',
    'Samples',
    'About product',
    'LBL card',
    'Tablet brand products',
  ];
  List<_DayPlan> _dayPlans = [
    _DayPlan(dayNumber: 1, visits: [_Visit(), _Visit(), _Visit()])
  ];
  final _notesCtrl = TextEditingController();
  DateTime _deadlineDate = DateTime.now();
  TimeOfDay _deadlineTime = const TimeOfDay(hour: 18, minute: 0);
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;

  List<_Doctor> get _filteredDoctors {
    if (_selectedArea == 'All Areas' || _selectedArea.trim().isEmpty) {
      return _doctors;
    }
    final target = _selectedArea.trim().toLowerCase();
    final matches = _doctors.where((d) => d.area.trim().toLowerCase() == target).toList();
    return matches.isNotEmpty ? matches : _doctors;
  }

  List<_Clinic> get _filteredClinics {
    if (_selectedArea == 'All Areas' || _selectedArea.trim().isEmpty) {
      return _clinics;
    }
    final target = _selectedArea.trim().toLowerCase();
    final matches = _clinics.where((c) => c.area.trim().toLowerCase() == target).toList();
    return matches.isNotEmpty ? matches : _clinics;
  }

  List<_DoctorClinicSuggestion> get _filteredCombinations {
    if (_selectedArea == 'All Areas' || _selectedArea.trim().isEmpty) {
      return _combinations;
    }
    final target = _selectedArea.trim().toLowerCase();
    final matches = _combinations.where((cb) {
      final a = cb.area.trim().toLowerCase();
      return a == target || cb.doctor.area.trim().toLowerCase() == target || cb.clinic.area.trim().toLowerCase() == target;
    }).toList();
    return matches.isNotEmpty ? matches : _combinations;
  }

  void _onTaskBasisChanged(String basis) {
    setState(() {
      _taskBasis = basis;
      if (basis == 'Daily') _dayPlans = [_dayPlans.first];
    });
  }

  @override
  void initState() {
    super.initState();
    _repLat = widget.repLat;
    _repLng = widget.repLng;
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    if (_repLat == null) _fetchLocation();
    _fetchDataFromDB();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<http.Response> _postRequest(String relativePath, Object body, {Duration timeout = const Duration(seconds: 6)}) async {
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base$relativePath');
        final res = await http.post(
          url,
          headers: AppConfig.headers,
          body: body,
        ).timeout(timeout);
        if (res.statusCode == 200 || res.statusCode == 201) {
          return res;
        }
      } catch (e) {
        debugPrint('[TaskScreen] POST error from $base: $e');
      }
    }
    throw Exception('Failed to connect to server');
  }

  Future<http.Response> _getRequest(String relativePath, {Duration timeout = const Duration(seconds: 6)}) async {
    for (final base in AppConfig.allHosts) {
      try {
        final url = Uri.parse('$base$relativePath');
        final res = await http.get(
          url,
          headers: AppConfig.headers,
        ).timeout(timeout);
        if (res.statusCode == 200) {
          return res;
        }
      } catch (e) {
        debugPrint('[TaskScreen] GET error from $base: $e');
      }
    }
    throw Exception('Failed to connect to server');
  }

  // ── Fetch doctors & clinics from DB ──────────────────────────────────────

  Future<void> _fetchDataFromDB() async {
    try {
      final qParams = '?user_id=${widget.salesRep.id}&role=${Uri.encodeComponent(widget.salesRep.role)}';
      final response = await _getRequest('/backend/get_data.php$qParams');
      final data = json.decode(response.body);
      final areasJson = (data['areas'] as List?) ?? [];
      final doctorsJson = (data['doctors'] as List?) ?? [];
      final clinicsJson = (data['clinics'] as List?) ?? [];
      final combosJson = (data['combinations'] as List?) ?? [];

      final List<_Doctor> loadedDoctors = doctorsJson
          .map((d) => _Doctor(
                d['name']?.toString() ?? '',
                d['speciality']?.toString() ?? '',
                d['phone']?.toString() ?? '',
                (d['id'] as num?)?.toInt(),
                (d['added_by'] as num?)?.toInt(),
                d['area']?.toString() ?? '',
              ))
          .toList();

      final List<_Clinic> loadedClinics = clinicsJson
          .map((c) => _Clinic(
                c['name']?.toString() ?? '',
                (c['lat'] as num?)?.toDouble() ?? 0.0,
                (c['lng'] as num?)?.toDouble() ?? 0.0,
                c['address']?.toString() ?? '',
                c['phone']?.toString() ?? '',
                (c['id'] as num?)?.toInt(),
                (c['added_by'] as num?)?.toInt(),
                c['area']?.toString() ?? '',
              ))
          .toList();

      final List<_DoctorClinicSuggestion> loadedCombos = [];
      for (final cb in combosJson) {
        final dName = cb['doctor_name']?.toString().trim() ?? '';
        final cName = cb['clinic_name']?.toString().trim() ?? '';
        final areaName = cb['area']?.toString().trim() ?? '';
        if (dName.isEmpty || cName.isEmpty) continue;

        _Doctor? matchedDoc;
        for (final d in loadedDoctors) {
          if (d.name.toLowerCase() == dName.toLowerCase() && (areaName.isEmpty || d.area.toLowerCase() == areaName.toLowerCase())) {
            matchedDoc = d;
            break;
          }
        }
        matchedDoc ??= _Doctor(dName, 'General Physician', '', null, null, areaName);

        _Clinic? matchedClin;
        for (final c in loadedClinics) {
          if (c.name.toLowerCase() == cName.toLowerCase() && (areaName.isEmpty || c.area.toLowerCase() == areaName.toLowerCase())) {
            matchedClin = c;
            break;
          }
        }
        matchedClin ??= _Clinic(
          cName,
          (cb['clinic_lat'] as num?)?.toDouble() ?? 0.0,
          (cb['clinic_lng'] as num?)?.toDouble() ?? 0.0,
          cb['clinic_address']?.toString() ?? '',
          '',
          null,
          null,
          areaName,
        );

        final suggestion = _DoctorClinicSuggestion(doctor: matchedDoc, clinic: matchedClin);
        if (!loadedCombos.any((item) => item.uniqueKey == suggestion.uniqueKey)) {
          loadedCombos.add(suggestion);
        }
      }

      final Set<String> loadedAreas = {'All Areas', 'Chennai', 'Villupuram', 'Cuddalore', 'Tindivanam'};
      for (final a in areasJson) {
        final str = a?.toString().trim() ?? '';
        if (str.isNotEmpty) loadedAreas.add(str);
      }
      for (final d in loadedDoctors) {
        if (d.area.trim().isNotEmpty) loadedAreas.add(d.area.trim());
      }
      for (final c in loadedClinics) {
        if (c.area.trim().isNotEmpty) loadedAreas.add(c.area.trim());
      }
      for (final cb in loadedCombos) {
        if (cb.area.trim().isNotEmpty) loadedAreas.add(cb.area.trim());
      }

      if (mounted) {
        setState(() {
          _areas = loadedAreas.toList();
          _doctors = loadedDoctors;
          _clinics = loadedClinics;
          _combinations = loadedCombos;
          _applyExistingTask();
          _isLoadingData = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _applyExistingTask();
          _isLoadingData = false;
        });
      }
    }
  }

  void _applyExistingTask() {
    if (widget.existingTask == null) return;
    final ext = widget.existingTask!;
    final basis = ext['task_basis'] as String?;
    if (basis != null && basis.isNotEmpty) {
      _taskBasis = basis;
    }
    final notes = ext['notes'] as String?;
    if (notes != null && notes.isNotEmpty) {
      _notesCtrl.text = notes;
    }

    final docName = ext['doctor_name'] as String? ?? '';
    final clinName = ext['clinic_name'] as String? ?? '';
    final areaName = ext['area'] as String? ?? '';
    final category = ext['task_category'] as String? ?? '';
    if (areaName.isNotEmpty) {
      _selectedArea = areaName;
      if (!_areas.contains(areaName)) _areas.add(areaName);
    }

    _Doctor? doc;
    if (docName.isNotEmpty) {
      for (final d in _doctors) {
        if (d.name.toLowerCase() == docName.toLowerCase() &&
            (areaName.isEmpty || d.area.toLowerCase() == areaName.toLowerCase())) {
          doc = d;
          break;
        }
      }
      doc ??= _Doctor(docName, 'General Physician', '', null, null, areaName);
      if (!_doctors.contains(doc)) _doctors.add(doc);
    }

    _Clinic? clin;
    if (clinName.isNotEmpty) {
      for (final c in _clinics) {
        if (c.name.toLowerCase() == clinName.toLowerCase() &&
            (areaName.isEmpty || c.area.toLowerCase() == areaName.toLowerCase())) {
          clin = c;
          break;
        }
      }
      if (clin == null) {
        final lat = (ext['clinic_lat'] as num?)?.toDouble() ?? 0.0;
        final lng = (ext['clinic_lng'] as num?)?.toDouble() ?? 0.0;
        final addr = ext['clinic_address'] as String? ?? '';
        clin = _Clinic(clinName, lat, lng, addr, '', null, null, areaName);
        _clinics.add(clin);
      }
    }

    if (doc != null && clin != null) {
      final pair = _DoctorClinicSuggestion(doctor: doc, clinic: clin);
      if (!_combinations.any((item) => item.uniqueKey == pair.uniqueKey)) {
        _combinations.add(pair);
      }
    }

    if (_dayPlans.isNotEmpty && _dayPlans.first.visits.isNotEmpty) {
      _dayPlans.first.visits.first.doctor = doc;
      _dayPlans.first.visits.first.clinic = clin;
      if (category.isNotEmpty) {
        if (!_taskCategories.contains(category)) {
          _taskCategories.add(category);
        }
        _dayPlans.first.visits.first.taskCategory = category;
      }
    }

    final deadlineRaw = (ext['deadline_date_time'] ?? ext['deadline']) as String?;
    if (deadlineRaw != null && deadlineRaw.isNotEmpty) {
      try {
        final dt = DateTime.parse(deadlineRaw);
        _deadlineDate = dt;
        _deadlineTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      } catch (_) {}
    }
  }

  Future<void> _openDoctorPicker(int dayIndex, int visitIndex) async {
    final visit = _dayPlans[dayIndex].visits[visitIndex];
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PickerSheet<_Doctor>(
        hint: _selectedArea != 'All Areas' ? 'Select Doctor in $_selectedArea' : 'Select or Search Doctor',
        items: _filteredDoctors,
        combinations: _filteredCombinations,
        selected: visit.doctor,
        label: (d) => d.name,
        subtitle: (d) {
          final parts = <String>[];
          if (d.area.isNotEmpty) parts.add('AREA: ${d.area.toUpperCase()}');
          if (d.speciality.isNotEmpty) parts.add(d.speciality);
          if (d.phone.isNotEmpty) parts.add(d.phone);
          return parts.join(' • ');
        },
        isDoctorPicker: true,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (result is _DoctorClinicSuggestion) {
          visit.doctor = result.doctor;
          visit.clinic = result.clinic;
        } else if (result is _Doctor) {
          visit.doctor = result;
        }
      });
    }
  }

  Future<void> _openClinicPicker(int dayIndex, int visitIndex) async {
    final visit = _dayPlans[dayIndex].visits[visitIndex];
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PickerSheet<_Clinic>(
        hint: _selectedArea != 'All Areas' ? 'Select Clinic in $_selectedArea' : 'Select or Search Clinic / Hospital',
        items: _filteredClinics,
        combinations: _filteredCombinations,
        selected: visit.clinic,
        label: (c) => c.name,
        subtitle: (c) {
          final parts = <String>[];
          if (c.area.isNotEmpty) parts.add('AREA: ${c.area.toUpperCase()}');
          if (c.address.isNotEmpty) {
            parts.add(c.address);
          } else if (c.lat != 0) {
            parts.add('Lat: ${c.lat.toStringAsFixed(4)}, Lng: ${c.lng.toStringAsFixed(4)}');
          }
          return parts.join(' • ');
        },
        isDoctorPicker: false,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (result is _DoctorClinicSuggestion) {
          visit.doctor = result.doctor;
          visit.clinic = result.clinic;
        } else if (result is _Clinic) {
          visit.clinic = result;
        }
      });
    }
  }

  // ── GPS location ──────────────────────────────────────────────────────────

  Future<void> _fetchLocation() async {
    setState(() { _loadingLoc = true; _locStatus = 'Fetching location...'; });
    try {
      bool svc = await Geolocator.isLocationServiceEnabled();
      if (!svc) { setState(() { _loadingLoc = false; _locStatus = 'Location services disabled'; }); return; }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() { _loadingLoc = false; _locStatus = 'Location permission denied'; }); return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() { _repLat = pos.latitude; _repLng = pos.longitude; _loadingLoc = false; _locStatus = ''; });
    } catch (e) {
      setState(() { _loadingLoc = false; _locStatus = 'Error: $e'; });
    }
  }

  // ── Add New Doctor dialog ─────────────────────────────────────────────────

  Future<void> _showAddDoctorDialog() async {
    final nameCtrl = TextEditingController();
    final specCtrl = TextEditingController(text: 'General Physician');
    final phoneCtrl = TextEditingController();
    final areaCtrl = TextEditingController(text: _selectedArea != 'All Areas' ? _selectedArea : '');
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.person_add_rounded, color: Color(0xFF00A86B)),
            SizedBox(width: 10),
            Text('Add New Doctor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _dialogField(nameCtrl, 'Doctor Name *', Icons.person_rounded,
                    validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
                const SizedBox(height: 12),
                _dialogField(specCtrl, 'Speciality', Icons.medical_services_rounded),
                const SizedBox(height: 12),
                _dialogField(phoneCtrl, 'Phone Number', Icons.phone_rounded,
                    type: TextInputType.phone),
                const SizedBox(height: 12),
                _dialogField(areaCtrl, 'Area / Division (e.g. Chennai)', Icons.location_city_rounded),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: saving ? null : () async {
                if (!formKey.currentState!.validate()) return;
                setS(() => saving = true);
                try {
                  final enteredArea = areaCtrl.text.trim();
                  final res = await _postRequest(
                    '/backend/add_doctor.php',
                    jsonEncode({
                      'name': nameCtrl.text.trim(),
                      'speciality': specCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                      'area': enteredArea,
                      'added_by': widget.salesRep.id,
                    }),
                  );
                  final data = json.decode(res.body);
                  if (data['success'] == true) {
                    final d = _Doctor(
                      data['doctor']?['name'] ?? nameCtrl.text.trim(),
                      data['doctor']?['speciality'] ?? specCtrl.text.trim(),
                      data['doctor']?['phone'] ?? phoneCtrl.text.trim(),
                      (data['doctor']?['id'] as num?)?.toInt(),
                      widget.salesRep.id,
                      data['doctor']?['area'] ?? enteredArea,
                    );
                    if (mounted) {
                      setState(() {
                        _doctors.add(d);
                        if (enteredArea.isNotEmpty && !_areas.contains(enteredArea)) {
                          _areas.add(enteredArea);
                        }
                      });
                    }
                    // Close dialog FIRST, then show snack using screen context
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) _snack('Doctor "${d.name}" added in area "${d.area.isNotEmpty ? d.area : 'General'}"!');
                  } else {
                    setS(() => saving = false);
                    if (mounted) _snack(data['message'] ?? 'Failed to add doctor.');
                  }
                } catch (_) {
                  final enteredArea = areaCtrl.text.trim();
                  final d = _Doctor(
                    nameCtrl.text.trim(),
                    specCtrl.text.trim(),
                    phoneCtrl.text.trim(),
                    DateTime.now().millisecondsSinceEpoch,
                    widget.salesRep.id,
                    enteredArea,
                  );
                  if (mounted) {
                    setState(() {
                      _doctors.add(d);
                      if (enteredArea.isNotEmpty && !_areas.contains(enteredArea)) {
                        _areas.add(enteredArea);
                      }
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _snack('Doctor "${d.name}" added locally (offline mode).');
                }
              },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose(); specCtrl.dispose(); phoneCtrl.dispose(); areaCtrl.dispose();
  }

  // ── Add New Clinic dialog ─────────────────────────────────────────────────

  Future<void> _showAddClinicDialog() async {
    final nameCtrl    = TextEditingController();
    final addrCtrl    = TextEditingController();
    final phoneCtrl   = TextEditingController();
    final areaCtrl    = TextEditingController();
    final mapUrlCtrl  = TextEditingController();
    final latCtrl     = TextEditingController();
    final lngCtrl     = TextEditingController();
    final formKey     = GlobalKey<FormState>();
    bool  saving      = false;
    bool  urlParsed   = false;
    bool  isExtracting= false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.local_hospital_rounded, color: Color(0xFF00A86B)),
            SizedBox(width: 10),
            Text('Add New Clinic',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _dialogField(nameCtrl, 'Clinic / Hospital Name *',
                    Icons.local_hospital_rounded,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null),
                const SizedBox(height: 12),
                _dialogField(addrCtrl, 'Address', Icons.place_rounded),
                const SizedBox(height: 12),
                _dialogField(phoneCtrl, 'Phone Number', Icons.phone_rounded,
                    type: TextInputType.phone),
                const SizedBox(height: 12),
                _dialogField(areaCtrl, 'Area / Division (e.g. Chennai)', Icons.location_city_rounded),
                const SizedBox(height: 12),
                TextFormField(
                  controller: mapUrlCtrl,
                  onChanged: (val) {
                    final localCoords = MapUrlService.extractCoordinatesFromText(val);
                    if (localCoords != null) {
                      setS(() {
                        latCtrl.text = localCoords['lat']!.toString();
                        lngCtrl.text = localCoords['lng']!.toString();
                        urlParsed = true;
                      });
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Paste Google Maps URL',
                    prefixIcon: const Icon(Icons.map_rounded, color: Color(0xFF00A86B), size: 20),
                    filled: true,
                    fillColor: const Color(0xFFF0FDF4),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD1FAE5))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD1FAE5))),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    suffixIcon: TextButton(
                      onPressed: isExtracting
                          ? null
                          : () async {
                              final url = mapUrlCtrl.text.trim();
                              if (url.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please paste a Google Maps URL first.'), backgroundColor: Colors.red),
                                );
                                return;
                              }
                              setS(() {
                                isExtracting = true;
                                urlParsed = false;
                              });

                              try {
                                final coords = await MapUrlService.resolveMapUrl(url);
                                if (coords != null) {
                                  setS(() {
                                    latCtrl.text = coords['lat']!.toString();
                                    lngCtrl.text = coords['lng']!.toString();
                                    urlParsed = true;
                                    isExtracting = false;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Coordinates extracted: Lat ${latCtrl.text}, Lng ${lngCtrl.text}'),
                                        backgroundColor: const Color(0xFF00A86B),
                                        duration: const Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                } else {
                                  setS(() {
                                    urlParsed = false;
                                    isExtracting = false;
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Could not extract coordinates from this URL.\nPlease enter Latitude & Longitude manually below.'),
                                        backgroundColor: Colors.orange,
                                        duration: Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                }
                              } catch (_) {
                                setS(() {
                                  urlParsed = false;
                                  isExtracting = false;
                                });
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Could not extract coordinates from this URL.\nPlease enter Latitude & Longitude manually below.'),
                                      backgroundColor: Colors.orange,
                                      duration: Duration(seconds: 4),
                                    ),
                                  );
                                }
                              }
                            },
                      child: isExtracting
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A86B)))
                          : const Text('Extract', style: TextStyle(color: Color(0xFF00A86B), fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ),
                ),
                if (urlParsed) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF047857), size: 14),
                      const SizedBox(width: 6),
                      Text('Lat: ${latCtrl.text}  Lng: ${lngCtrl.text}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF047857), fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Or enter coordinates manually:', style: TextStyle(fontSize: 11, color: Color(0xFF52796F))),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: _dialogField(latCtrl, 'Latitude', Icons.south_rounded, type: TextInputType.numberWithOptions(decimal: true, signed: true))),
                  const SizedBox(width: 8),
                  Expanded(child: _dialogField(lngCtrl, 'Longitude', Icons.east_rounded, type: TextInputType.numberWithOptions(decimal: true, signed: true))),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: saving ? null : () async {
                if (!formKey.currentState!.validate()) return;
                final lat = double.tryParse(latCtrl.text.trim()) ?? 0;
                final lng = double.tryParse(lngCtrl.text.trim()) ?? 0;
                if (lat == 0 || lng == 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please provide valid latitude and longitude.'), backgroundColor: Colors.red),
                  );
                  return;
                }
                setS(() => saving = true);
                final enteredArea = areaCtrl.text.trim();
                try {
                  final res = await _postRequest(
                    '/backend/add_clinic.php',
                    jsonEncode({
                      'name': nameCtrl.text.trim(),
                      'address': addrCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                      'map_url': mapUrlCtrl.text.trim(),
                      'area': enteredArea,
                      'lat': lat,
                      'lng': lng,
                      'added_by': widget.salesRep.id,
                    }),
                  );
                  final data = json.decode(res.body);
                  if (data['success'] == true) {
                    final dClinic = data['clinic'] ?? {};
                    final c = _Clinic(
                      dClinic['name'] ?? nameCtrl.text.trim(),
                      (dClinic['lat'] as num?)?.toDouble() ?? lat,
                      (dClinic['lng'] as num?)?.toDouble() ?? lng,
                      dClinic['address'] ?? addrCtrl.text.trim(),
                      dClinic['phone'] ?? phoneCtrl.text.trim(),
                      (dClinic['id'] as num?)?.toInt(),
                      widget.salesRep.id,
                      dClinic['area'] ?? enteredArea,
                    );
                    if (mounted) {
                      setState(() {
                        _clinics.add(c);
                        if (enteredArea.isNotEmpty && !_areas.contains(enteredArea)) {
                          _areas.add(enteredArea);
                        }
                      });
                    }
                    // Close dialog FIRST, then show snack using screen context
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) _snack('Clinic "${c.name}" added in area "${c.area.isNotEmpty ? c.area : 'General'}"!');
                  } else {
                    setS(() => saving = false);
                    if (mounted) _snack(data['message'] ?? 'Failed to add clinic.');
                  }
                } catch (_) {
                  final c = _Clinic(
                    nameCtrl.text.trim(),
                    lat,
                    lng,
                    addrCtrl.text.trim(),
                    phoneCtrl.text.trim(),
                    DateTime.now().millisecondsSinceEpoch,
                    widget.salesRep.id,
                    enteredArea,
                  );
                  if (mounted) {
                    setState(() {
                      _clinics.add(c);
                      if (enteredArea.isNotEmpty && !_areas.contains(enteredArea)) {
                        _areas.add(enteredArea);
                      }
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) _snack('Clinic "${c.name}" added locally (offline mode).');
                }
              },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose(); addrCtrl.dispose(); phoneCtrl.dispose(); areaCtrl.dispose();
    mapUrlCtrl.dispose(); latCtrl.dispose(); lngCtrl.dispose();
  }

  // ── Add New Area / Division dialog ────────────────────────────────────────

  Future<void> _showAddAreaDialog() async {
    final areaCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool saving = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.add_location_alt_rounded, color: Color(0xFF00A86B)),
            SizedBox(width: 10),
            Text('Add New Area', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dialogField(
                  areaCtrl,
                  'Area / Division Name * (e.g. Coimbatore)',
                  Icons.location_city_rounded,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Area name is required';
                    if (v.trim().toLowerCase() == 'all areas') return 'Cannot use reserved name "All Areas"';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00A86B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final enteredArea = areaCtrl.text.trim();
                      setS(() => saving = true);
                      try {
                        final res = await _postRequest(
                          '/backend/add_area.php',
                          jsonEncode({
                            'name': enteredArea,
                            'added_by': widget.salesRep.id,
                          }),
                        );
                        final data = json.decode(res.body);
                        if (data['success'] == true) {
                          if (mounted) {
                            setState(() {
                              if (!_areas.any((a) => a.toLowerCase() == enteredArea.toLowerCase())) {
                                _areas.add(enteredArea);
                              }
                              _selectedArea = enteredArea;
                            });
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) _snack('Area "$enteredArea" added successfully!');
                        } else {
                          setS(() => saving = false);
                          if (mounted) _snack(data['message'] ?? 'Failed to add area.');
                        }
                      } catch (_) {
                        if (mounted) {
                          setState(() {
                            if (!_areas.any((a) => a.toLowerCase() == enteredArea.toLowerCase())) {
                              _areas.add(enteredArea);
                            }
                            _selectedArea = enteredArea;
                          });
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _snack('Area "$enteredArea" added locally (offline mode).');
                      }
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
    areaCtrl.dispose();
  }

  // ── Reusable dialog field ─────────────────────────────────────────────────

  Widget _dialogField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType type = TextInputType.text, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: type,
      validator: validator,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1B4332), fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        prefixIcon: Icon(icon, size: 18, color: const Color(0xFF00A86B)),
        filled: true,
        fillColor: const Color(0xFFF0FDF4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD1FAE5))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD1FAE5))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00A86B), width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
      ),
    );
  }

  // ── Assign task ───────────────────────────────────────────────────────────

  Future<void> _assignTask() async {
    final List<_Visit> filledVisits = [];
    final List<String> dayLabels = [];

    for (int i = 0; i < _dayPlans.length; i++) {
      final visits = _dayPlans[i].visits;
      for (int j = 0; j < visits.length; j++) {
        final v = visits[j];
        final hasAny = v.doctor != null || v.clinic != null || v.taskCategory != null;
        if (hasAny || visits.length == 1) {
          if (v.doctor == null) {
            _snack('Please select a Doctor for Day ${i + 1}, Visit ${j + 1}.');
            return;
          }
          if (v.clinic == null) {
            _snack('Please select a Clinic for Day ${i + 1}, Visit ${j + 1}.');
            return;
          }
          if (v.taskCategory == null) {
            _snack('Please select a Task Category for Day ${i + 1}, Visit ${j + 1}.');
            return;
          }
          filledVisits.add(v);
          dayLabels.add(_taskBasis == 'Daily' ? 'Daily' : 'Day ${i + 1}');
        }
      }
    }

    if (filledVisits.isEmpty) {
      _snack('Please select at least one Doctor and Clinic.');
      return;
    }

    final int? existingTaskId = (widget.existingTask?['id'] as num?)?.toInt();
    final List<Map<String, dynamic>> assignedTasks = [];

    final deadlineDateTime = DateTime(
      _deadlineDate.year,
      _deadlineDate.month,
      _deadlineDate.day,
      _deadlineTime.hour,
      _deadlineTime.minute,
    );
    final formattedDeadline = DateFormat('yyyy-MM-dd HH:mm:ss').format(deadlineDateTime);

    for (int i = 0; i < filledVisits.length; i++) {
      final v = filledVisits[i];
      final dayLabel = dayLabels[i];
      final taskIdForVisit = (i == 0) ? existingTaskId : null;
      final taskArea = v.clinic!.area.isNotEmpty ? v.clinic!.area : v.doctor!.area;
      await _saveTaskToDB(
        taskId: taskIdForVisit,
        taskBasis: dayLabel,
        doctorName: v.doctor!.name,
        clinic: v.clinic!,
        category: v.taskCategory ?? '',
        notes: _notesCtrl.text.trim(),
        deadlineDateTime: formattedDeadline,
        area: taskArea,
      );
      assignedTasks.add({
        if (taskIdForVisit != null) 'taskId': taskIdForVisit,
        'doctorName': v.doctor!.name,
        'clinicName': v.clinic!.name,
        'area': taskArea,
        'clinicLat': v.clinic!.lat,
        'clinicLng': v.clinic!.lng,
        'clinicAddress': v.clinic!.address,
        'taskCategory': v.taskCategory ?? '',
        'taskBasis': dayLabel,
        'notes': _notesCtrl.text.trim(),
        'deadline_date_time': formattedDeadline,
      });
    }

    if (!mounted) return;
    final firstVisit = filledVisits.first;
    Navigator.of(context).pop({
      if (existingTaskId != null) 'taskId': existingTaskId,
      'taskBasis': _taskBasis, 'repName': widget.salesRep.name,
      'repLat': _repLat, 'repLng': _repLng,
      'doctorName': firstVisit.doctor!.name,
      'clinicName': firstVisit.clinic!.name,
      'area': firstVisit.clinic!.area.isNotEmpty ? firstVisit.clinic!.area : firstVisit.doctor!.area,
      'taskCategory': firstVisit.taskCategory,
      'clinicLat': firstVisit.clinic!.lat, 'clinicLng': firstVisit.clinic!.lng,
      'clinicAddress': firstVisit.clinic!.address,
      'notes': _notesCtrl.text.trim(),
      'deadline_date_time': formattedDeadline,
      'assignedTasks': assignedTasks,
    });
  }

  Future<void> _saveTaskToDB({
    int? taskId,
    required String taskBasis,
    required String doctorName,
    required _Clinic clinic,
    required String category,
    required String notes,
    String? deadlineDateTime,
    String? area,
  }) async {
    try {
      final taskArea = (area != null && area.isNotEmpty)
          ? area
          : (clinic.area.isNotEmpty ? clinic.area : '');
      final Map<String, dynamic> body = {
        'user_id': widget.salesRep.id,
        'sales_rep_name': widget.salesRep.name,
        'task_basis': taskBasis,
        'doctor_name': doctorName,
        'clinic_name': clinic.name,
        'task_category': category,
        'area': taskArea,
        'source_lat': _repLat ?? 0.0,
        'source_lng': _repLng ?? 0.0,
        'clinic_lat': clinic.lat,
        'clinic_lng': clinic.lng,
        'clinic_address': clinic.address,
        'notes': notes,
        if (deadlineDateTime != null) 'deadline_date_time': deadlineDateTime,
      };
      if (taskId != null && taskId > 0) {
        body['task_id'] = taskId;
      }
      await _postRequest(
        '/backend/save_task.php',
        jsonEncode(body),
      );
    } catch (_) {}
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: const Color(0xFF00A86B),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Show All Areas / Divisions Management Modal ────────────────────────────

  Future<void> _showShowAllAreasModal() async {
    final manageableAreas = _areas.where((a) => a != 'All Areas').toList();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => _AreaManagementModal(
        areas: manageableAreas,
        doctors: _doctors,
        clinics: _clinics,
        salesRep: widget.salesRep,
        onAddNewArea: _showAddAreaDialog,
        onDeleteSelected: (selectedAreas) async {
          await _executeDeleteAreas(selectedAreas);
        },
      ),
    );
  }

  Future<void> _executeDeleteAreas(List<String> areasToDelete) async {
    if (areasToDelete.isEmpty) {
      _snack('No areas selected for deletion.');
      return;
    }

    try {
      final res = await _postRequest(
        '/backend/delete_doctor_clinic.php',
        jsonEncode({
          'user_id': widget.salesRep.id,
          'role': widget.salesRep.role,
          'area_names': areasToDelete,
        }),
      );

      final data = json.decode(res.body);
      if (data['success'] == true) {
        if (mounted) {
          setState(() {
            _areas.removeWhere((a) => areasToDelete.contains(a));
            if (areasToDelete.contains(_selectedArea)) {
              _selectedArea = 'All Areas';
            }
            _doctors = _doctors.map((d) => areasToDelete.contains(d.area)
                ? _Doctor(d.name, d.speciality, d.phone, d.id, d.addedBy, '')
                : d).toList();
            _clinics = _clinics.map((c) => areasToDelete.contains(c.area)
                ? _Clinic(c.name, c.lat, c.lng, c.address, c.phone, c.id, c.addedBy, '')
                : c).toList();
            _combinations = _combinations.map((cb) => areasToDelete.contains(cb.area)
                ? _DoctorClinicSuggestion(
                    doctor: areasToDelete.contains(cb.doctor.area)
                        ? _Doctor(cb.doctor.name, cb.doctor.speciality, cb.doctor.phone, cb.doctor.id, cb.doctor.addedBy, '')
                        : cb.doctor,
                    clinic: areasToDelete.contains(cb.clinic.area)
                        ? _Clinic(cb.clinic.name, cb.clinic.lat, cb.clinic.lng, cb.clinic.address, cb.clinic.phone, cb.clinic.id, cb.clinic.addedBy, '')
                        : cb.clinic,
                  )
                : cb).toList();
          });

          final totalCount = areasToDelete.length;
          _showUndoAreaSnackBar(
            message: '$totalCount area${totalCount == 1 ? '' : 's'} deleted.',
            deletedAreas: areasToDelete,
          );
        }
      } else {
        if (mounted) _snack(data['message'] ?? 'Failed to delete areas.');
      }
    } catch (e) {
      debugPrint('Delete areas error: $e');
      if (mounted) _snack('Could not delete areas. Please check connection.');
    }
  }

  void _showUndoAreaSnackBar({
    required String message,
    required List<String> deletedAreas,
  }) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1E293B),
        duration: const Duration(seconds: 7),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: const Color(0xFF34D399),
          onPressed: () => _restoreDeletedAreas(deletedAreas),
        ),
      ),
    );
  }

  Future<void> _restoreDeletedAreas(List<String> areasToRestore) async {
    try {
      final res = await _postRequest(
        '/backend/restore_doctor_clinic.php',
        jsonEncode({
          'user_id': widget.salesRep.id,
          'role': widget.salesRep.role,
          'area_names': areasToRestore,
        }),
      );

      final data = json.decode(res.body);
      if (data['success'] == true) {
        if (mounted) {
          setState(() {
            for (final a in areasToRestore) {
              if (!_areas.contains(a)) {
                _areas.add(a);
              }
            }
          });
          _snack('Areas restored successfully!');
        }
      } else {
        if (mounted) _snack(data['message'] ?? 'Failed to restore areas.');
      }
    } catch (_) {
      if (mounted) _snack('Could not restore areas. Connection error.');
    }
  }

  // ── Show All Doctors / Clinics Management Modal ────────────────────────────

  Future<void> _showShowAllDoctorsClinicsModal() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => _DoctorClinicManagementModal(
        doctors: _doctors,
        clinics: _clinics,
        salesRep: widget.salesRep,
        onDeleteSelected: (selectedDocs, selectedClinics) async {
          await _executeDeleteDoctorsAndClinics(selectedDocs, selectedClinics);
        },
      ),
    );
  }

  Future<void> _executeDeleteDoctorsAndClinics(
    List<_Doctor> docsToDelete,
    List<_Clinic> clinicsToDelete,
  ) async {
    final docIds = docsToDelete.map((d) => d.id).whereType<int>().where((id) => id > 0).toList();
    final docNames = docsToDelete.map((d) => d.name).toList();
    final clinIds = clinicsToDelete.map((c) => c.id).whereType<int>().where((id) => id > 0).toList();
    final clinNames = clinicsToDelete.map((c) => c.name).toList();

    if (docsToDelete.isEmpty && clinicsToDelete.isEmpty) {
      _snack('No records selected for deletion.');
      return;
    }

    try {
      final res = await _postRequest(
        '/backend/delete_doctor_clinic.php',
        jsonEncode({
          'user_id': widget.salesRep.id,
          'role': widget.salesRep.role,
          'doctor_ids': docIds,
          'doctor_names': docNames,
          'clinic_ids': clinIds,
          'clinic_names': clinNames,
        }),
      );

      final data = json.decode(res.body);
      if (data['success'] == true) {
        if (mounted) {
          setState(() {
            _doctors.removeWhere((d) => docsToDelete.contains(d) || docNames.contains(d.name) || (d.id != null && docIds.contains(d.id)));
            _clinics.removeWhere((c) => clinicsToDelete.contains(c) || clinNames.contains(c.name) || (c.id != null && clinIds.contains(c.id)));

            // Clear any active visit references if the item was deleted
            for (final plan in _dayPlans) {
              for (final visit in plan.visits) {
                if (visit.doctor != null && (docsToDelete.contains(visit.doctor) || docNames.contains(visit.doctor!.name) || (visit.doctor!.id != null && docIds.contains(visit.doctor!.id)))) {
                  visit.doctor = null;
                }
                if (visit.clinic != null && (clinicsToDelete.contains(visit.clinic) || clinNames.contains(visit.clinic!.name) || (visit.clinic!.id != null && clinIds.contains(visit.clinic!.id)))) {
                  visit.clinic = null;
                }
              }
            }
          });

          final totalCount = docsToDelete.length + clinicsToDelete.length;
          _showUndoSnackBar(
            message: '$totalCount item${totalCount == 1 ? '' : 's'} deleted.',
            deletedDocs: docsToDelete,
            deletedClinics: clinicsToDelete,
          );
        }
      } else {
        if (mounted) _snack(data['message'] ?? 'Failed to delete records.');
      }
    } catch (e) {
      debugPrint('Delete error: $e');
      if (mounted) _snack('Could not delete records. Please check connection.');
    }
  }

  void _showUndoSnackBar({
    required String message,
    required List<_Doctor> deletedDocs,
    required List<_Clinic> deletedClinics,
  }) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF1E293B),
        duration: const Duration(seconds: 7),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: const Color(0xFF34D399),
          onPressed: () => _restoreDeletedRecords(deletedDocs, deletedClinics),
        ),
      ),
    );
  }

  Future<void> _restoreDeletedRecords(
    List<_Doctor> docsToRestore,
    List<_Clinic> clinicsToRestore,
  ) async {
    final docIds = docsToRestore.map((d) => d.id).whereType<int>().where((id) => id > 0).toList();
    final docNames = docsToRestore.map((d) => d.name).toList();
    final clinIds = clinicsToRestore.map((c) => c.id).whereType<int>().where((id) => id > 0).toList();
    final clinNames = clinicsToRestore.map((c) => c.name).toList();

    try {
      final res = await _postRequest(
        '/backend/restore_doctor_clinic.php',
        jsonEncode({
          'user_id': widget.salesRep.id,
          'role': widget.salesRep.role,
          'doctor_ids': docIds,
          'doctor_names': docNames,
          'clinic_ids': clinIds,
          'clinic_names': clinNames,
        }),
      );

      final data = json.decode(res.body);
      if (data['success'] == true) {
        if (mounted) {
          setState(() {
            for (final doc in docsToRestore) {
              if (!_doctors.any((d) => (doc.id != null && d.id == doc.id) || d.name == doc.name)) {
                _doctors.add(doc);
              }
            }
            for (final clin in clinicsToRestore) {
              if (!_clinics.any((c) => (clin.id != null && c.id == clin.id) || c.name == clin.name)) {
                _clinics.add(clin);
              }
            }
          });
          _snack('Restored successfully!');
        }
      } else {
        if (mounted) _snack(data['message'] ?? 'Failed to restore records.');
      }
    } catch (_) {
      if (mounted) _snack('Could not restore records. Connection error.');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF5),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _BlobPainter())),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: Column(children: [
                  _buildTopBar(),
                  Expanded(
                    child: _isLoadingData
                        ? const Center(child: CircularProgressIndicator(color: Color(0xFF00A86B)))
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _buildSection(icon: Icons.calendar_today_rounded, title: 'Task Basis', child: _buildRadioRow()),
                              const SizedBox(height: 16),
                              _buildSection(icon: Icons.badge_rounded, title: 'Medical Representative', child: _buildRepInfo()),
                              const SizedBox(height: 16),
                              _buildAssignmentsSection(),
                              const SizedBox(height: 16),
                              _buildSection(icon: Icons.alarm_rounded, title: 'Task Deadline', child: _buildDeadlineSection()),
                              const SizedBox(height: 16),
                              _buildSection(icon: Icons.notes_rounded, title: 'Task Notes (optional)', child: _buildNotes()),
                              const SizedBox(height: 28),
                              _buildAssignButton(),
                            ]),
                          ),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlineSection() {
    final dateFormat = DateFormat('EEE, dd MMM yyyy');
    final timeFormat = DateFormat('hh:mm a');
    final dt = DateTime(
      _deadlineDate.year,
      _deadlineDate.month,
      _deadlineDate.day,
      _deadlineTime.hour,
      _deadlineTime.minute,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _deadlineDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Color(0xFF00A86B),
                            onPrimary: Colors.white,
                            onSurface: Color(0xFF1B4332),
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setState(() => _deadlineDate = picked);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD1FAE5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 18, color: Color(0xFF00A86B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Due Date', style: TextStyle(fontSize: 10, color: Color(0xFF52796F), fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(dateFormat.format(_deadlineDate), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B4332))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _deadlineTime,
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Color(0xFF00A86B),
                            onPrimary: Colors.white,
                            onSurface: Color(0xFF1B4332),
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    setState(() => _deadlineTime = picked);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFD1FAE5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 18, color: Color(0xFF00A86B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Due Time', style: TextStyle(fontSize: 10, color: Color(0xFF52796F), fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(timeFormat.format(dt), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1B4332))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Target completion date and time evaluated for on-time performance points.',
          style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(children: [
        _GlassBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: () => Navigator.of(context).pop()),
        const SizedBox(width: 14),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF00A86B), Color(0xFF047857)]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: const Color(0xFF00A86B).withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Assign Task', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1B4332))),
          Text('MedSafe LifeScience', style: TextStyle(fontSize: 11, color: Color(0xFF52796F))),
        ]),
      ]),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 16, color: const Color(0xFF065F46)),
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1B4332), letterSpacing: 0.2)),
            ]),
            if (trailing != null) trailing,
          ],
        ),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  Widget _buildRadioRow() {
    return Row(
      children: ['Daily', 'Weekly', 'Monthly'].map((basis) {
        final selected = _taskBasis == basis;
        return Expanded(
          child: GestureDetector(
            onTap: () => _onTaskBasisChanged(basis),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFF00A86B) : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? const Color(0xFF00A86B) : const Color(0xFFD1FAE5), width: 1.5),
                boxShadow: selected ? [BoxShadow(color: const Color(0xFF00A86B).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))] : [],
              ),
              child: Column(children: [
                Radio<String>(
                  value: basis, groupValue: _taskBasis,
                  onChanged: (v) => setState(() => _taskBasis = v!),
                  activeColor: Colors.white,
                  fillColor: WidgetStateProperty.resolveWith((s) => selected ? Colors.white : const Color(0xFF00A86B)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(height: 2),
                Text(basis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : const Color(0xFF1B4332))),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRepInfo() {
    return Column(children: [
      _infoTile(icon: Icons.person_rounded, label: 'Representative Name', value: widget.salesRep.name),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFD1FAE5))),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.my_location_rounded, size: 16, color: Color(0xFF065F46))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Current Location', style: TextStyle(fontSize: 11, color: Color(0xFF52796F), fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            _loadingLoc
                ? Row(children: [
                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00A86B))),
                    const SizedBox(width: 8),
                    Text(_locStatus, style: const TextStyle(fontSize: 12, color: Color(0xFF52796F))),
                  ])
                : _repLat != null
                    ? Text('Lat: ${_repLat!.toStringAsFixed(6)}  |  Lng: ${_repLng!.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1B4332)))
                    : Text(_locStatus.isNotEmpty ? _locStatus : 'Location unavailable',
                        style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
          ])),
          if (!_loadingLoc)
            GestureDetector(
              onTap: _fetchLocation,
              child: Container(padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFF00A86B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF00A86B))),
            ),
        ]),
      ),
    ]);
  }

  Widget _buildAssignmentsSection() {
    return Column(children: [
      // ── Area / Division Filter & Show All Controls ──
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD1FAE5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.location_city_rounded, size: 16, color: Color(0xFF065F46)),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Area / Division Filter',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1B4332)),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showShowAllAreasModal,
                  icon: const Icon(Icons.manage_accounts_rounded, size: 15, color: Color(0xFF00A86B)),
                  label: const Text('SHOW ALL', style: TextStyle(color: Color(0xFF00A86B), fontWeight: FontWeight.w800, fontSize: 11)),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFF0FDF4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFD1FAE5))),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _styledDropdown<String>(
                    hint: 'Select Area / Division',
                    value: _selectedArea,
                    items: _areas,
                    label: (a) => a == 'All Areas' ? 'All Areas (Show All Records)' : 'Area: $a',
                    onChanged: (a) {
                      if (a != null) {
                        setState(() => _selectedArea = a);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _addBtn(onTap: _showAddAreaDialog, tooltip: 'Add new area / division'),
              ],
            ),
          ],
        ),
      ),
      for (int i = 0; i < _dayPlans.length; i++) ...[
        _buildSection(
          icon: Icons.assignment_ind_rounded,
          title: _taskBasis == 'Daily' ? 'Task Assignment' : 'Day ${i + 1} Assignment',
          trailing: TextButton.icon(
            onPressed: _showShowAllDoctorsClinicsModal,
            icon: const Icon(Icons.manage_accounts_rounded, size: 15, color: Color(0xFF00A86B)),
            label: const Text('SHOW ALL', style: TextStyle(color: Color(0xFF00A86B), fontWeight: FontWeight.w800, fontSize: 11)),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFFF0FDF4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFD1FAE5))),
            ),
          ),
          child: Column(children: [
            for (int vIndex = 0; vIndex < _dayPlans[i].visits.length; vIndex++) ...[
              if (vIndex > 0) const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: Color(0xFFE2E8F0), thickness: 1.2),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(8)),
                    child: Text('Visit #${vIndex + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                  ),
                  if (_dayPlans[i].visits.length > 1)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                      tooltip: 'Remove Visit',
                      onPressed: () => setState(() => _dayPlans[i].visits.removeAt(vIndex)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // ── Doctor row with autocomplete & + button ──
              Row(children: [
                Expanded(
                  child: _DoctorAutocompleteField(
                    selectedDoctor: _dayPlans[i].visits[vIndex].doctor,
                    doctors: _filteredDoctors,
                    combinations: _filteredCombinations,
                    onDoctorSelected: (d) => setState(() => _dayPlans[i].visits[vIndex].doctor = d),
                    onSuggestionSelected: (s) => setState(() {
                      _dayPlans[i].visits[vIndex].doctor = s.doctor;
                      _dayPlans[i].visits[vIndex].clinic = s.clinic;
                    }),
                    onOpenPicker: () => _openDoctorPicker(i, vIndex),
                    onAddNew: _showAddDoctorDialog,
                  ),
                ),
                const SizedBox(width: 8),
                _addBtn(onTap: _showAddDoctorDialog, tooltip: 'Add new doctor'),
              ]),
              const SizedBox(height: 12),
              // ── Clinic row with autocomplete & + button ──
              Row(children: [
                Expanded(
                  child: _ClinicAutocompleteField(
                    selectedClinic: _dayPlans[i].visits[vIndex].clinic,
                    clinics: _filteredClinics,
                    combinations: _filteredCombinations,
                    onClinicSelected: (c) => setState(() => _dayPlans[i].visits[vIndex].clinic = c),
                    onSuggestionSelected: (s) => setState(() {
                      _dayPlans[i].visits[vIndex].doctor = s.doctor;
                      _dayPlans[i].visits[vIndex].clinic = s.clinic;
                    }),
                    onOpenPicker: () => _openClinicPicker(i, vIndex),
                    onAddNew: _showAddClinicDialog,
                  ),
                ),
                const SizedBox(width: 8),
                _addBtn(onTap: _showAddClinicDialog, tooltip: 'Add new clinic'),
              ]),
              const SizedBox(height: 12),
              // ── Task Type / Category dropdown ──
              _styledDropdown<String>(
                hint: 'Select Task Item (Gifts, Samples, etc.)',
                value: _dayPlans[i].visits[vIndex].taskCategory,
                items: _taskCategories,
                label: (cat) => cat,
                onChanged: (cat) => setState(() => _dayPlans[i].visits[vIndex].taskCategory = cat),
              ),
              if (_dayPlans[i].visits[vIndex].clinic != null) ...[
                const SizedBox(height: 10),
                _buildClinicLocationBanner(_dayPlans[i].visits[vIndex].clinic!),
              ],
            ],
            const SizedBox(height: 14),
            // ── Button to add another doctor visit to this day ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _dayPlans[i].visits.add(_Visit())),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00A86B),
                    side: const BorderSide(color: Color(0xFF00A86B), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(
                    _taskBasis == 'Daily' ? '+ Add Doctor / Clinic Visit' : '+ Add Visit to Day ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _showShowAllDoctorsClinicsModal,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF065F46),
                    backgroundColor: const Color(0xFFF0FDF4),
                    side: const BorderSide(color: Color(0xFFA7F3D0), width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.manage_search_rounded, size: 17),
                  label: const Text(
                    'Show All / Manage',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                if (_dayPlans[i].visits.length < 3)
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        while (_dayPlans[i].visits.length < 3) {
                          _dayPlans[i].visits.add(_Visit());
                        }
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFECFDF5),
                      foregroundColor: const Color(0xFF047857),
                      elevation: 0,
                      side: const BorderSide(color: Color(0xFFA7F3D0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.alt_route_rounded, size: 16),
                    label: const Text(
                      '3 Tasks (Route Comparison)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ]),
        ),
        const SizedBox(height: 16),
      ],
      if (_taskBasis == 'Weekly' && _dayPlans.length < 7) _buildAddDayButton(),
      if (_taskBasis == 'Monthly' && _dayPlans.length < 31) _buildAddDayButton(),
    ]);
  }

  Widget _addBtn({required VoidCallback onTap, required String tooltip}) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: const Color(0xFF00A86B), borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: const Color(0xFF00A86B).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _buildAddDayButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _dayPlans.add(_DayPlan(dayNumber: _dayPlans.length + 1))),
        icon: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF00A86B)),
        label: Text('Add Day ${_dayPlans.length + 1}', style: const TextStyle(color: Color(0xFF00A86B), fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildClinicLocationBanner(_Clinic clinic) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFD1FAE5))),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF065F46))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const Text('Clinic Location', style: TextStyle(fontSize: 11, color: Color(0xFF52796F), fontWeight: FontWeight.w500)),
              if (clinic.area.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Text(
                    'AREA: ${clinic.area.toUpperCase()}',
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8)),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text('Lat: ${clinic.lat.toStringAsFixed(6)}  |  Lng: ${clinic.lng.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1B4332))),
          Text(clinic.address, style: const TextStyle(fontSize: 11, color: Color(0xFF52796F))),
        ])),
      ]),
    );
  }

  Widget _buildNotes() {
    return TextField(
      controller: _notesCtrl, maxLines: 3,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        hintText: 'Enter task description or instructions...',
        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        filled: true, fillColor: const Color(0xFFF0FDF4),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD1FAE5))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD1FAE5))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF00A86B), width: 1.5)),
        contentPadding: const EdgeInsets.all(12),
      ),
    );
  }

  Widget _buildAssignButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _assignTask,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00A86B), foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 6, shadowColor: const Color(0xFF00A86B).withValues(alpha: 0.45),
        ),
        icon: const Icon(Icons.check_circle_rounded, size: 22),
        label: const Text('OK / Assign Task', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
      ),
    );
  }

  Widget _infoTile({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFD1FAE5))),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 16, color: const Color(0xFF065F46))),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF52796F), fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1B4332))),
        ])),
      ]),
    );
  }

  // ── Custom bottom-sheet picker (replaces DropdownButton to avoid
  //    the _dependents.isEmpty assertion crash on mobile devices) ────────────
  Widget _styledDropdown<T>({
    required String hint,
    required T? value,
    required List<T> items,
    required String Function(T) label,
    String Function(T)? subtitle,
    required void Function(T?) onChanged,
  }) {
    final displayText = value != null ? label(value) : null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (items.isEmpty) {
          _snack('No items available. Please add one first.');
          return;
        }
        final picked = await showModalBottomSheet<T>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => _PickerSheet<T>(
            hint: hint,
            items: items,
            selected: value,
            label: label,
            subtitle: subtitle,
          ),
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD1FAE5), width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText ?? hint,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: displayText != null ? FontWeight.w700 : FontWeight.w400,
                  color: displayText != null
                      ? const Color(0xFF1B4332)
                      : const Color(0xFF94A3B8),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF00A86B), size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

class _GlassBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD1FAE5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Center(child: Icon(icon, size: 17, color: const Color(0xFF1E293B))),
      ),
    );
  }
}

// ─── Doctor Autocomplete Field Widget ────────────────────────────────────────

class _DoctorAutocompleteField extends StatefulWidget {
  final _Doctor? selectedDoctor;
  final List<_Doctor> doctors;
  final List<_DoctorClinicSuggestion> combinations;
  final void Function(_Doctor doctor) onDoctorSelected;
  final void Function(_DoctorClinicSuggestion suggestion) onSuggestionSelected;
  final VoidCallback onOpenPicker;
  final VoidCallback onAddNew;

  const _DoctorAutocompleteField({
    required this.selectedDoctor,
    required this.doctors,
    required this.combinations,
    required this.onDoctorSelected,
    required this.onSuggestionSelected,
    required this.onOpenPicker,
    required this.onAddNew,
  });

  @override
  State<_DoctorAutocompleteField> createState() => _DoctorAutocompleteFieldState();
}

class _DoctorAutocompleteFieldState extends State<_DoctorAutocompleteField> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.selectedDoctor != null) {
      _textController.text = widget.selectedDoctor!.name;
    }
  }

  @override
  void didUpdateWidget(covariant _DoctorAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedDoctor != oldWidget.selectedDoctor) {
      final newText = widget.selectedDoctor?.name ?? '';
      if (_textController.text != newText && !_focusNode.hasFocus) {
        _textController.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Object>(
      textEditingController: _textController,
      focusNode: _focusNode,
      displayStringForOption: (option) {
        if (option is _DoctorClinicSuggestion) {
          return option.doctor.name;
        } else if (option is _Doctor) {
          return option.name;
        }
        return '';
      },
      optionsBuilder: (TextEditingValue textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) {
          return const Iterable<Object>.empty();
        }

        final List<Object> results = [];

        // Matching Doctor + Clinic combinations
        final matchingCombos = widget.combinations.where((c) {
          final doc = c.doctor.name.toLowerCase();
          final clin = c.clinic.name.toLowerCase();
          final spec = c.doctor.speciality.toLowerCase();
          return doc.contains(q) || clin.contains(q) || spec.contains(q);
        }).toList();
        results.addAll(matchingCombos);

        // Matching Doctors that are not already listed
        final matchingDocs = widget.doctors.where((d) {
          final name = d.name.toLowerCase();
          final spec = d.speciality.toLowerCase();
          final inCombos = matchingCombos.any((c) =>
              (c.doctor.id != null && d.id != null && c.doctor.id == d.id) ||
              c.doctor.name.toLowerCase() == d.name.toLowerCase());
          return (name.contains(q) || spec.contains(q)) && !inCombos;
        }).toList();
        results.addAll(matchingDocs);

        return results;
      },
      onSelected: (option) {
        if (option is _DoctorClinicSuggestion) {
          _textController.text = option.doctor.name;
          widget.onSuggestionSelected(option);
        } else if (option is _Doctor) {
          _textController.text = option.name;
          widget.onDoctorSelected(option);
        }
        _focusNode.unfocus();
      },
      fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focusNode.hasFocus ? const Color(0xFF00A86B) : const Color(0xFFD1FAE5),
              width: focusNode.hasFocus ? 1.5 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B4332),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Select or Type Doctor...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w400),
                    prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF00A86B), size: 18),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF94A3B8)),
                            onPressed: () {
                              controller.clear();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF00A86B), size: 20),
                tooltip: 'Browse Doctors',
                onPressed: widget.onOpenPicker,
              ),
            ],
          ),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, unused) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  if (option is _DoctorClinicSuggestion) {
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.hub_rounded, size: 16, color: Color(0xFF065F46)),
                      ),
                      title: Text(
                        '${option.doctor.name} — ${option.clinic.name}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1B4332)),
                      ),
                      subtitle: Text(
                        option.subtitle,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF52796F)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: const Text('Pair', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                      ),
                      onTap: () => onSelected(option),
                    );
                  } else if (option is _Doctor) {
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.person_rounded, size: 16, color: Color(0xFF4B5563)),
                      ),
                      title: Text(
                        option.name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                      ),
                      subtitle: Text(
                        [
                          if (option.area.isNotEmpty) 'AREA: ${option.area.toUpperCase()}',
                          if (option.speciality.isNotEmpty) option.speciality,
                          if (option.phone.isNotEmpty) option.phone,
                        ].join(' • '),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                      ),
                      onTap: () => onSelected(option),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Clinic Autocomplete Field Widget ────────────────────────────────────────

class _ClinicAutocompleteField extends StatefulWidget {
  final _Clinic? selectedClinic;
  final List<_Clinic> clinics;
  final List<_DoctorClinicSuggestion> combinations;
  final void Function(_Clinic clinic) onClinicSelected;
  final void Function(_DoctorClinicSuggestion suggestion) onSuggestionSelected;
  final VoidCallback onOpenPicker;
  final VoidCallback onAddNew;

  const _ClinicAutocompleteField({
    required this.selectedClinic,
    required this.clinics,
    required this.combinations,
    required this.onClinicSelected,
    required this.onSuggestionSelected,
    required this.onOpenPicker,
    required this.onAddNew,
  });

  @override
  State<_ClinicAutocompleteField> createState() => _ClinicAutocompleteFieldState();
}

class _ClinicAutocompleteFieldState extends State<_ClinicAutocompleteField> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    if (widget.selectedClinic != null) {
      _textController.text = widget.selectedClinic!.name;
    }
  }

  @override
  void didUpdateWidget(covariant _ClinicAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedClinic != oldWidget.selectedClinic) {
      final newText = widget.selectedClinic?.name ?? '';
      if (_textController.text != newText && !_focusNode.hasFocus) {
        _textController.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Object>(
      textEditingController: _textController,
      focusNode: _focusNode,
      displayStringForOption: (option) {
        if (option is _DoctorClinicSuggestion) {
          return option.clinic.name;
        } else if (option is _Clinic) {
          return option.name;
        }
        return '';
      },
      optionsBuilder: (TextEditingValue textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) {
          return const Iterable<Object>.empty();
        }

        final List<Object> results = [];

        // Matching Doctor + Clinic combinations
        final matchingCombos = widget.combinations.where((c) {
          final doc = c.doctor.name.toLowerCase();
          final clin = c.clinic.name.toLowerCase();
          final addr = c.clinic.address.toLowerCase();
          return doc.contains(q) || clin.contains(q) || addr.contains(q);
        }).toList();
        results.addAll(matchingCombos);

        // Matching Clinics that are not already listed
        final matchingClinics = widget.clinics.where((c) {
          final name = c.name.toLowerCase();
          final addr = c.address.toLowerCase();
          final inCombos = matchingCombos.any((item) =>
              (item.clinic.id != null && c.id != null && item.clinic.id == c.id) ||
              item.clinic.name.toLowerCase() == c.name.toLowerCase());
          return (name.contains(q) || addr.contains(q)) && !inCombos;
        }).toList();
        results.addAll(matchingClinics);

        return results;
      },
      onSelected: (option) {
        if (option is _DoctorClinicSuggestion) {
          _textController.text = option.clinic.name;
          widget.onSuggestionSelected(option);
        } else if (option is _Clinic) {
          _textController.text = option.name;
          widget.onClinicSelected(option);
        }
        _focusNode.unfocus();
      },
      fieldViewBuilder: (ctx, controller, focusNode, onFieldSubmitted) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focusNode.hasFocus ? const Color(0xFF00A86B) : const Color(0xFFD1FAE5),
              width: focusNode.hasFocus ? 1.5 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1B4332),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Select or Type Clinic / Hospital...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontWeight: FontWeight.w400),
                    prefixIcon: const Icon(Icons.local_hospital_outlined, color: Color(0xFF00A86B), size: 18),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16, color: Color(0xFF94A3B8)),
                            onPressed: () {
                              controller.clear();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF00A86B), size: 20),
                tooltip: 'Browse Clinics',
                onPressed: widget.onOpenPicker,
              ),
            ],
          ),
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, unused) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  if (option is _DoctorClinicSuggestion) {
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.hub_rounded, size: 16, color: Color(0xFF065F46)),
                      ),
                      title: Text(
                        '${option.doctor.name} — ${option.clinic.name}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1B4332)),
                      ),
                      subtitle: Text(
                        option.subtitle,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF52796F)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: const Text('Pair', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF047857))),
                      ),
                      onTap: () => onSelected(option),
                    );
                  } else if (option is _Clinic) {
                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.local_hospital_rounded, size: 16, color: Color(0xFF4B5563)),
                      ),
                      title: Text(
                        option.name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                      ),
                      subtitle: Text(
                        [
                          if (option.area.isNotEmpty) 'AREA: ${option.area.toUpperCase()}',
                          if (option.address.isNotEmpty) option.address else 'Lat: ${option.lat.toStringAsFixed(4)}, Lng: ${option.lng.toStringAsFixed(4)}',
                        ].join(' • '),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                      ),
                      onTap: () => onSelected(option),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Bottom-sheet picker widget (no intrinsic height issues) ─────────────────

class _PickerSheet<T> extends StatefulWidget {
  final String hint;
  final List<T> items;
  final List<_DoctorClinicSuggestion>? combinations;
  final T? selected;
  final String Function(T) label;
  final String Function(T)? subtitle;
  final bool isDoctorPicker;

  const _PickerSheet({
    required this.hint,
    required this.items,
    this.combinations,
    required this.selected,
    required this.label,
    this.subtitle,
    this.isDoctorPicker = false,
  });

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();

    final filtered = q.isEmpty
        ? widget.items
        : widget.items.where((item) {
            final name = widget.label(item).toLowerCase();
            final sub = widget.subtitle?.call(item).toLowerCase() ?? '';
            return name.contains(q) || sub.contains(q);
          }).toList();

    final matchingCombos = (widget.combinations ?? []).where((item) {
      if (q.isEmpty) return false;
      final docName = item.doctor.name.toLowerCase();
      final clinName = item.clinic.name.toLowerCase();
      final spec = item.doctor.speciality.toLowerCase();
      final addr = item.clinic.address.toLowerCase();
      return docName.contains(q) || clinName.contains(q) || spec.contains(q) || addr.contains(q);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Handle ──
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            // ── Title ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.list_rounded, size: 16, color: Color(0xFF065F46)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.hint,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B4332),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            // ── Search box ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(fontSize: 13, color: Color(0xFF1B4332)),
                decoration: InputDecoration(
                  hintText: 'Search by Doctor or Clinic name, address...',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00A86B), size: 20),
                  suffixIcon: _search.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF94A3B8)),
                          onPressed: () => setState(() => _search = ''),
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF0FDF4),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD1FAE5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD1FAE5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00A86B), width: 1.5),
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            // ── Items list ──
            Expanded(
              child: (filtered.isEmpty && matchingCombos.isEmpty)
                  ? const Center(
                      child: Text(
                        'No results found',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    )
                  : ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      children: [
                        // If matching doctor+clinic combinations exist
                        if (matchingCombos.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            color: const Color(0xFFF0FDF4),
                            child: Row(
                              children: [
                                const Icon(Icons.hub_rounded, size: 14, color: Color(0xFF047857)),
                                const SizedBox(width: 6),
                                Text(
                                  'MATCHING DOCTOR & CLINIC PAIRS (${matchingCombos.length})',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF065F46), letterSpacing: 0.5),
                                ),
                              ],
                            ),
                          ),
                          for (final combo in matchingCombos)
                            InkWell(
                              onTap: () => Navigator.pop(ctx, combo),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD1FAE5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.hub_rounded, size: 16, color: Color(0xFF065F46)),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${combo.doctor.name} — ${combo.clinic.name}',
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1B4332)),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            combo.subtitle,
                                            style: const TextStyle(fontSize: 11, color: Color(0xFF52796F)),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF00A86B)),
                                  ],
                                ),
                              ),
                            ),
                          if (filtered.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                              color: const Color(0xFFF8FAFC),
                              child: Row(
                                children: [
                                  Icon(widget.isDoctorPicker ? Icons.medical_services_rounded : Icons.local_hospital_rounded, size: 14, color: const Color(0xFF475569)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'INDIVIDUAL RECORDS (${filtered.length})',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF475569), letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        // Individual records
                        for (int i = 0; i < filtered.length; i++) ...[
                          Builder(builder: (_) {
                            final item = filtered[i];
                            final isSelected = item == widget.selected;
                            final sub = widget.subtitle?.call(item);
                            return InkWell(
                              onTap: () => Navigator.pop(ctx, item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFD1FAE5) : Colors.transparent,
                                  border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            widget.label(item),
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: isSelected ? const Color(0xFF065F46) : const Color(0xFF1B4332),
                                            ),
                                          ),
                                          if (sub != null && sub.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              sub,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isSelected ? const Color(0xFF047857) : const Color(0xFF52796F),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (isSelected)
                                      const Icon(Icons.check_circle_rounded, color: Color(0xFF00A86B), size: 20),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(Offset(size.width * 0.9, size.height * 0.08), size.width * 0.4,
        Paint()..color = const Color(0xFF00A86B).withValues(alpha: 0.06));
    canvas.drawCircle(Offset(size.width * 0.05, size.height * 0.88), size.width * 0.35,
        Paint()..color = const Color(0xFF52B788).withValues(alpha: 0.04));
  }
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ─── Show All Areas / Divisions Management Modal ──────────────────────────────

class _AreaManagementModal extends StatefulWidget {
  final List<String> areas;
  final List<_Doctor> doctors;
  final List<_Clinic> clinics;
  final User salesRep;
  final Future<void> Function(List<String> selectedAreas) onDeleteSelected;
  final VoidCallback? onAddNewArea;

  const _AreaManagementModal({
    required this.areas,
    required this.doctors,
    required this.clinics,
    required this.salesRep,
    required this.onDeleteSelected,
    this.onAddNewArea,
  });

  @override
  State<_AreaManagementModal> createState() => _AreaManagementModalState();
}

class _AreaManagementModalState extends State<_AreaManagementModal> {
  String _search = '';
  final Set<String> _selectedAreas = {};
  bool _isProcessing = false;

  int _doctorCountForArea(String area) {
    return widget.doctors.where((d) => d.area.trim().toLowerCase() == area.trim().toLowerCase()).length;
  }

  int _clinicCountForArea(String area) {
    return widget.clinics.where((c) => c.area.trim().toLowerCase() == area.trim().toLowerCase()).length;
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();
    final filteredAreas = widget.areas.where((a) {
      if (q.isEmpty) return true;
      return a.toLowerCase().contains(q);
    }).toList();

    final totalSelected = _selectedAreas.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Drag handle ──
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),

            // ── Modal Header ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.location_city_rounded, size: 20, color: Color(0xFF065F46)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show All Areas / Divisions',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1B4332)),
                        ),
                        Text(
                          'Select and delete obsolete or unused areas',
                          style: TextStyle(fontSize: 11, color: Color(0xFF52796F)),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onAddNewArea != null)
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 22, color: Color(0xFF00A86B)),
                      tooltip: 'Add New Area',
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onAddNewArea!();
                      },
                    ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),

            // ── Search bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(fontSize: 13, color: Color(0xFF1B4332)),
                decoration: InputDecoration(
                  hintText: 'Search areas by name (e.g. Chennai, Villupuram)...',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00A86B), size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF0FDF4),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD1FAE5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD1FAE5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00A86B), width: 1.5),
                  ),
                ),
              ),
            ),

            // ── Selection toolbar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$totalSelected selected',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: totalSelected > 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedAreas.addAll(filteredAreas);
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Select All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00A86B))),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: totalSelected == 0
                            ? null
                            : () {
                                setState(() {
                                  _selectedAreas.clear();
                                });
                              },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: totalSelected > 0 ? Colors.redAccent : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // ── List of Areas ──
            Expanded(
              child: filteredAreas.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No areas found matching your search',
                          style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: filteredAreas.length,
                      itemBuilder: (context, index) {
                        final area = filteredAreas[index];
                        final isSelected = _selectedAreas.contains(area);
                        final docCount = _doctorCountForArea(area);
                        final clinCount = _clinicCountForArea(area);

                        return Container(
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFFEF2F2) : Colors.transparent,
                            border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedAreas.add(area);
                                    } else {
                                      _selectedAreas.remove(area);
                                    }
                                  });
                                },
                                activeColor: const Color(0xFFDC2626),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.location_on_rounded, size: 18, color: Color(0xFF2563EB)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      area,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (docCount == 0 && clinCount == 0)
                                          ? 'No doctors or clinics registered'
                                          : [
                                              if (docCount > 0) '$docCount Doctor${docCount == 1 ? '' : 's'}',
                                              if (clinCount > 0) '$clinCount Clinic${clinCount == 1 ? '' : 's'}',
                                            ].join('  •  '),
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // ── Sticky Bottom Delete Bar ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: (totalSelected == 0 || _isProcessing)
                        ? null
                        : () => _confirmAndDeleteAreas(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: totalSelected > 0 ? 3 : 0,
                    ),
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.delete_forever_rounded, size: 20),
                    label: Text(
                      totalSelected == 0
                          ? 'Select areas to delete'
                          : 'DELETE SELECTED ($totalSelected)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDeleteAreas(BuildContext modalContext) async {
    final totalSelected = _selectedAreas.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            const SizedBox(width: 8),
            Text('Delete $totalSelected Area${totalSelected == 1 ? '' : 's'}?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the selected $totalSelected area(s)?\n\n'
          'They will be removed from the Area dropdown and selection filters. Historical tasks and completed reports will remain intact.',
          style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final selectedList = _selectedAreas.toList();
      if (modalContext.mounted) {
        Navigator.pop(modalContext);
      }
      await widget.onDeleteSelected(selectedList);
    }
  }
}

// ─── Show All Doctors / Clinics Management Modal ──────────────────────────────

class _DoctorClinicManagementModal extends StatefulWidget {
  final List<_Doctor> doctors;
  final List<_Clinic> clinics;
  final User salesRep;
  final Future<void> Function(List<_Doctor> selectedDocs, List<_Clinic> selectedClinics) onDeleteSelected;

  const _DoctorClinicManagementModal({
    required this.doctors,
    required this.clinics,
    required this.salesRep,
    required this.onDeleteSelected,
  });

  @override
  State<_DoctorClinicManagementModal> createState() => _DoctorClinicManagementModalState();
}

class _DoctorClinicManagementModalState extends State<_DoctorClinicManagementModal> {
  String _tab = 'all'; // 'all', 'doctors', 'clinics'
  String _search = '';
  final Set<_Doctor> _selectedDocs = {};
  final Set<_Clinic> _selectedClinics = {};
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final q = _search.trim().toLowerCase();

    final filteredDocs = widget.doctors.where((d) {
      if (q.isEmpty) return true;
      return d.name.toLowerCase().contains(q) ||
          d.speciality.toLowerCase().contains(q) ||
          d.phone.toLowerCase().contains(q);
    }).toList();

    final filteredClinics = widget.clinics.where((c) {
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.address.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q);
    }).toList();

    final totalSelected = _selectedDocs.length + _selectedClinics.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Drag handle ──
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),

            // ── Modal Header ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1FAE5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.manage_accounts_rounded, size: 20, color: Color(0xFF065F46)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Show All Doctors & Clinics',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1B4332)),
                        ),
                        Text(
                          'Select and delete incorrect or obsolete records',
                          style: TextStyle(fontSize: 11, color: Color(0xFF52796F)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),

            // ── Filter Tabs ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  _buildTabPill('all', 'All (${widget.doctors.length + widget.clinics.length})'),
                  const SizedBox(width: 8),
                  _buildTabPill('doctors', 'Doctors (${widget.doctors.length})'),
                  const SizedBox(width: 8),
                  _buildTabPill('clinics', 'Clinics (${widget.clinics.length})'),
                ],
              ),
            ),

            // ── Search bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _search = v),
                style: const TextStyle(fontSize: 13, color: Color(0xFF1B4332)),
                decoration: InputDecoration(
                  hintText: 'Search by name, address, speciality, phone...',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                  prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00A86B), size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF0FDF4),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD1FAE5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD1FAE5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00A86B), width: 1.5),
                  ),
                ),
              ),
            ),

            // ── Selection toolbar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$totalSelected selected',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: totalSelected > 0 ? const Color(0xFFDC2626) : const Color(0xFF64748B),
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (_tab == 'all' || _tab == 'doctors') {
                              _selectedDocs.addAll(filteredDocs);
                            }
                            if (_tab == 'all' || _tab == 'clinics') {
                              _selectedClinics.addAll(filteredClinics);
                            }
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Select All', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00A86B))),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: totalSelected == 0
                            ? null
                            : () {
                                setState(() {
                                  _selectedDocs.clear();
                                  _selectedClinics.clear();
                                });
                              },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: totalSelected > 0 ? Colors.redAccent : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // ── List of Doctors and Clinics ──
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  if (_tab == 'all' || _tab == 'doctors') ...[
                    if (_tab == 'all' && filteredDocs.isNotEmpty)
                      _buildSubHeader('Doctors (${filteredDocs.length})', Icons.medical_services_rounded),
                    for (final doc in filteredDocs)
                      _buildDoctorItem(doc),
                  ],
                  if (_tab == 'all' || _tab == 'clinics') ...[
                    if (_tab == 'all' && filteredClinics.isNotEmpty)
                      _buildSubHeader('Clinics / Hospitals (${filteredClinics.length})', Icons.local_hospital_rounded),
                    for (final clin in filteredClinics)
                      _buildClinicItem(clin),
                  ],
                  if ((_tab == 'doctors' && filteredDocs.isEmpty) ||
                      (_tab == 'clinics' && filteredClinics.isEmpty) ||
                      (_tab == 'all' && filteredDocs.isEmpty && filteredClinics.isEmpty))
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No records found matching your search',
                          style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Sticky Bottom Delete Bar ──
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: (totalSelected == 0 || _isProcessing)
                        ? null
                        : () => _confirmAndDelete(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      disabledBackgroundColor: const Color(0xFFE2E8F0),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: const Color(0xFF94A3B8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: totalSelected > 0 ? 3 : 0,
                    ),
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.delete_forever_rounded, size: 20),
                    label: Text(
                      totalSelected == 0
                          ? 'Select items to delete'
                          : 'DELETE SELECTED ($totalSelected)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabPill(String id, String label) {
    final isSelected = _tab == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = id),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF00A86B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.white : const Color(0xFF475569),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildSubHeader(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Icon(icon, size: 14, color: const Color(0xFF047857)),
          const SizedBox(width: 6),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF065F46),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctorItem(_Doctor doc) {
    final isSelected = _selectedDocs.contains(doc);

    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedDocs.remove(doc);
          } else {
            _selectedDocs.add(doc);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFEF2F2) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedDocs.add(doc);
                  } else {
                    _selectedDocs.remove(doc);
                  }
                });
              },
              activeColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.person_rounded, size: 18, color: Color(0xFF047857)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (doc.area.isNotEmpty) 'AREA: ${doc.area.toUpperCase()}',
                      if (doc.speciality.isNotEmpty) doc.speciality,
                      if (doc.phone.isNotEmpty) doc.phone,
                    ].join('  •  '),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClinicItem(_Clinic clin) {
    final isSelected = _selectedClinics.contains(clin);

    return InkWell(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedClinics.remove(clin);
          } else {
            _selectedClinics.add(clin);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFEF2F2) : Colors.transparent,
          border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1)),
        ),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedClinics.add(clin);
                  } else {
                    _selectedClinics.remove(clin);
                  }
                });
              },
              activeColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E7FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.local_hospital_rounded, size: 18, color: Color(0xFF4338CA)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clin.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (clin.area.isNotEmpty) 'AREA: ${clin.area.toUpperCase()}',
                      if (clin.address.isNotEmpty) clin.address else 'Lat: ${clin.lat.toStringAsFixed(4)}, Lng: ${clin.lng.toStringAsFixed(4)}',
                    ].join('  •  '),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext modalContext) async {
    final totalSelected = _selectedDocs.length + _selectedClinics.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            const SizedBox(width: 8),
            Text('Delete $totalSelected Record${totalSelected == 1 ? '' : 's'}?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete the selected $totalSelected Doctor/Clinic record(s)?\n\n'
          'They will be removed from your active selection lists. Historical tasks and completed reports will remain unaffected.',
          style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final selectedDocsList = _selectedDocs.toList();
      final selectedClinicsList = _selectedClinics.toList();

      if (modalContext.mounted) {
        Navigator.pop(modalContext);
      }
      await widget.onDeleteSelected(selectedDocsList, selectedClinicsList);
    }
  }
}
