import 'package:flutter/material.dart';

import '../data/sample_data.dart';

class MeetupLocationScreen extends StatefulWidget {
  const MeetupLocationScreen({super.key, this.selected});

  final String? selected;

  @override
  State<MeetupLocationScreen> createState() => _MeetupLocationScreenState();
}

class _MeetupLocationScreenState extends State<MeetupLocationScreen> {
  late String _selected = widget.selected ?? meetupLocations.first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Campus meetup map')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            height: 210,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF4FF),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFD6E6F7)),
            ),
            child: Stack(
              children: [
                const Center(
                  child: Icon(
                    Icons.map_rounded,
                    size: 92,
                    color: Color(0xFF0B2D5B),
                  ),
                ),
                ...List.generate(meetupLocations.length, (index) {
                  final left = 28.0 + (index * 58) % 250;
                  final top = 36.0 + (index * 31) % 130;
                  final location = meetupLocations[index];
                  return Positioned(
                    left: left,
                    top: top,
                    child: Icon(
                      Icons.location_on_rounded,
                      color: location == _selected
                          ? const Color(0xFF1BA86D)
                          : const Color(0xFF0B2D5B),
                      size: location == _selected ? 34 : 26,
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Mock campus map. Add a Google Maps API key and google_maps_flutter later to replace this placeholder.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ...meetupLocations.map(
            (location) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.shield_rounded),
                  title: Text(location),
                  subtitle: Text(safetyNotes[location]!),
                  trailing: FilledButton(
                    onPressed: () {
                      setState(() => _selected = location);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$location selected.')),
                      );
                    },
                    child: Text(location == _selected ? 'Selected' : 'Select'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
