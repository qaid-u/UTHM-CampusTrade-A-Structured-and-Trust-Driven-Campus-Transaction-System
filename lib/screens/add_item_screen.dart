import 'package:flutter/material.dart';

import '../data/sample_data.dart';
import '../models/item_model.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../widgets/custom_button.dart';

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  String _category = categories.first;
  String _condition = conditions[2];
  String _location = meetupLocations.first;
  late final AnimationController _success;

  @override
  void initState() {
    super.initState();
    _success = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _success.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post an item')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 1, end: 1.04).animate(
                CurvedAnimation(parent: _success, curve: Curves.elasticOut),
              ),
              child: Container(
                height: 142,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF4FF),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD6E6F7)),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_rounded,
                      size: 42,
                      color: Color(0xFF0B2D5B),
                    ),
                    SizedBox(height: 8),
                    Text('Image upload placeholder'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  _field(_name, 'Item name', Icons.sell_rounded),
                  _dropdown(
                    'Category',
                    Icons.category_rounded,
                    _category,
                    categories,
                    (value) => setState(() => _category = value!),
                  ),
                  _field(
                    _description,
                    'Description',
                    Icons.notes_rounded,
                    maxLines: 4,
                  ),
                  _field(
                    _price,
                    'Price (RM)',
                    Icons.payments_rounded,
                    keyboardType: TextInputType.number,
                  ),
                  _dropdown(
                    'Condition',
                    Icons.verified_rounded,
                    _condition,
                    conditions,
                    (value) => setState(() => _condition = value!),
                  ),
                  _dropdown(
                    'Preferred meetup location',
                    Icons.place_rounded,
                    _location,
                    meetupLocations,
                    (value) => setState(() => _location = value!),
                  ),
                  const SizedBox(height: 12),
                  CustomButton(
                    label: 'Submit listing',
                    icon: Icons.publish_rounded,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'Required field.';
          if (label.startsWith('Price') &&
              (double.tryParse(value.trim()) == null ||
                  double.parse(value.trim()) <= 0)) {
            return 'Enter a valid price.';
          }
          return null;
        },
      ),
    );
  }

  Widget _dropdown(
    String label,
    IconData icon,
    String value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        items: values
            .map((item) => DropdownMenuItem(value: item, child: Text(item)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final item = ItemModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sellerId: AuthService.instance.currentUser!.id,
      title: _name.text.trim(),
      category: _category,
      description: _description.text.trim(),
      price: double.parse(_price.text.trim()),
      condition: _condition,
      imageLabel: _category
          .substring(0, _category.length < 4 ? _category.length : 4)
          .toUpperCase(),
      meetupLocation: _location,
      createdAt: DateTime.now(),
      isFeatured: DatabaseService.instance.items.length.isEven,
    );
    await DatabaseService.instance.addItem(item);
    _success.forward(from: 0);
    _name.clear();
    _description.clear();
    _price.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text('Listing saved and added to marketplace.')),
          ],
        ),
      ),
    );
  }
}
