import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class MeetupLocationScreen extends StatefulWidget {
  const MeetupLocationScreen({super.key, this.selected});

  final String? selected;

  @override
  State<MeetupLocationScreen> createState() => _MeetupLocationScreenState();
}

class _MeetupLocationScreenState extends State<MeetupLocationScreen> {
  GoogleMapController? _mapController;
  LatLng _selectedLatLng = const LatLng(1.8538, 103.0863); // Center of UTHM Campus
  String _selectedAddress = 'UTHM Parit Raja Campus';
  bool _isLocating = false;
  bool _isGeocoding = false;

  // Predefined Safe Meetup Locations inside UTHM Campus
  static const List<Map<String, dynamic>> _presetLocations = [
    {
      'name': 'UTHM Library Lobby',
      'lat': 1.8576,
      'lng': 103.0872,
      'desc': 'Bright indoor area with security staff nearby.',
    },
    {
      'name': 'Student Centre (HEPA)',
      'lat': 1.8538,
      'lng': 103.0863,
      'desc': 'Busy student hub suitable for daytime meetups.',
    },
    {
      'name': 'Masa Cafe / Cafeteria',
      'lat': 1.8548,
      'lng': 103.0890,
      'desc': 'Public cafeteria area with steady student traffic.',
    },
    {
      'name': 'G3 Hall Entrance',
      'lat': 1.8529,
      'lng': 103.0848,
      'desc': 'Visible central campus meeting area.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _determineInitialPosition();
  }

  /// Handles GPS permissions and centers the map on current user location
  Future<void> _determineInitialPosition() async {
    if (kIsWeb) {
      _selectPreset(_presetLocations.first);
      return;
    }

    if (!mounted) return;
    setState(() => _isLocating = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        final userLatLng = LatLng(position.latitude, position.longitude);
        if (mounted) {
          setState(() {
            _selectedLatLng = userLatLng;
          });
        }
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: userLatLng, zoom: 16.5),
          ),
        );
        await _reverseGeocode(userLatLng);
      } else {
        // Fallback to library coordinates
        _selectPreset(_presetLocations.first);
      }
    } catch (e) {
      debugPrint('Geolocator failed: $e');
      _selectPreset(_presetLocations.first);
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  /// Reverse geocodes the coordinates into a human-readable street address using free OS geocoder
  Future<void> _reverseGeocode(LatLng latLng) async {
    if (!mounted) return;
    setState(() => _isGeocoding = true);
    try {
      final placemarks = await placemarkFromCoordinates(
        latLng.latitude,
        latLng.longitude,
      ).timeout(const Duration(seconds: 4));

      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final name = p.name ?? '';
        final street = p.street ?? '';
        final locality = p.locality ?? 'Parit Raja';
        final address = name == street ? name : '$name, $street';
        if (mounted) {
          setState(() {
            _selectedAddress = '$address, $locality'.replaceAll(', null', '');
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _selectedAddress = 'Location: ${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
          });
        }
      }
    } catch (e) {
      debugPrint('Geocoding failed: $e');
      if (mounted) {
        setState(() {
          _selectedAddress = 'Location: ${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isGeocoding = false);
      }
    }
  }

  void _selectPreset(Map<String, dynamic> preset) {
    final latLng = LatLng(preset['lat'] as double, preset['lng'] as double);
    setState(() {
      _selectedLatLng = latLng;
      _selectedAddress = preset['name'] as String;
    });
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: latLng, zoom: 16.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campus Meetup Map'),
        actions: [
          if (_isLocating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.my_location),
              onPressed: kIsWeb ? null : _determineInitialPosition,
            )
        ],
      ),
      body: Stack(
        children: [
          _buildMapArea(),

          // Search / Address Card Overlay
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.redAccent, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Selected Location',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          if (_isGeocoding)
                            const SizedBox(
                              height: 18,
                              child: LinearProgressIndicator(),
                            )
                          else
                            Text(
                              _selectedAddress,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Custom Zoom Controls & Predefined Safe Spots sliding carousel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 10, spreadRadius: 2),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
                    child: Text(
                      'SAFE & POPULAR CAMPUS MEETUP SPOTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),

                  // Carousel List
                  SizedBox(
                    height: 85,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: _presetLocations.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final preset = _presetLocations[index];
                        final isChosen = _selectedAddress == preset['name'];

                        return GestureDetector(
                          onTap: () => _selectPreset(preset),
                          child: Container(
                            width: 220,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isChosen ? Colors.blue.shade50 : Colors.grey.shade50,
                              border: Border.all(
                                color: isChosen ? Colors.blue : Colors.grey.shade300,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  preset['name'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: isChosen ? Colors.blue.shade800 : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  preset['desc'] as String,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Action Confirmation Button
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isGeocoding
                            ? null
                            : () {
                                // Pop and return selected meetup location data
                                Navigator.pop(context, {
                                  'location': _selectedAddress,
                                  'latitude': _selectedLatLng.latitude,
                                  'longitude': _selectedLatLng.longitude,
                                });
                              },
                        icon: const Icon(Icons.check_circle, size: 20),
                        label: const Text(
                          'CONFIRM MEETUP LOCATION',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapArea() {
    if (kIsWeb) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFFEAF3FF),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 120, 24, 210),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  size: 72,
                  color: Colors.blue,
                ),
                const SizedBox(height: 16),
                Text(
                  _selectedAddress,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B2D63),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_selectedLatLng.latitude.toStringAsFixed(4)}, ${_selectedLatLng.longitude.toStringAsFixed(4)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Choose a safe campus meetup spot below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: _selectedLatLng,
        zoom: 16.0,
      ),
      onMapCreated: (controller) => _mapController = controller,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      markers: {
        Marker(
          markerId: const MarkerId('meetup_pin'),
          position: _selectedLatLng,
          draggable: true,
          onDragEnd: (newPosition) {
            setState(() => _selectedLatLng = newPosition);
            _reverseGeocode(newPosition);
          },
          infoWindow: InfoWindow(
            title: 'Meetup Point',
            snippet: _selectedAddress,
          ),
        ),
      },
      onTap: (clickedLatLng) {
        setState(() => _selectedLatLng = clickedLatLng);
        _reverseGeocode(clickedLatLng);
      },
    );
  }
}
