import 'package:flutter/material.dart';

class MeetupLocationScreen extends StatefulWidget {
  const MeetupLocationScreen({super.key, this.selected});

  final String? selected;

  @override
  State<MeetupLocationScreen> createState() => _MeetupLocationScreenState();
}

class _MeetupLocationScreenState extends State<MeetupLocationScreen> {
  late String _selected = widget.selected ?? _meetupLocations.first;

  static const List<String> _meetupLocations = [
    'UTHM Library Lobby',
    'Student Centre',
    'Cafeteria Area',
    'Faculty Entrance',
    'Main Hall',
  ];

  static const Map<String, String> _safetyNotes = {
    'UTHM Library Lobby': 'Bright indoor area with staff nearby.',
    'Student Centre': 'Busy student space suitable for daytime meetups.',
    'Cafeteria Area': 'Public food court area with steady foot traffic.',
    'Faculty Entrance': 'Meet near the guard-visible entrance area.',
    'Main Hall': 'Open central location for quick exchanges.',
  };

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
            ),
            child: const Center(child: Icon(Icons.map_rounded, size: 80)),
          ),

          const SizedBox(height: 16),

          ..._meetupLocations.map((location) {
            final selected = location == _selected;

            return Card(
              child: ListTile(
                title: Text(location),
                subtitle: Text(_safetyNotes[location] ?? ''),
                trailing: FilledButton(
                  onPressed: () {
                    setState(() => _selected = location);
                    Navigator.pop(context, location);
                  },
                  child: Text(selected ? 'Selected' : 'Select'),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
