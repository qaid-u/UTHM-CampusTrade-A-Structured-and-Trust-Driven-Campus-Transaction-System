import '../models/item_model.dart';
import '../models/user_model.dart';

const categories = [
  'Textbooks',
  'Electronics',
  'Clothes',
  'Room Items',
  'Sports',
  'Others',
];

const conditions = ['New', 'Like New', 'Good', 'Fair', 'Used'];

const meetupLocations = [
  'UTHM Library Lobby',
  'Student Centre',
  'Cafeteria Area',
  'Faculty Entrance',
  'Main Hall',
];

const safetyNotes = {
  'UTHM Library Lobby': 'Bright indoor area with staff nearby.',
  'Student Centre': 'Busy student space suitable for daytime meetups.',
  'Cafeteria Area': 'Public food court area with steady foot traffic.',
  'Faculty Entrance': 'Meet near the guard-visible entrance area.',
  'Main Hall': 'Open central location for quick exchanges.',
};

final sampleUsers = [
  const UserModel(
    id: 'u1',
    name: 'Aina Rahman',
    studentId: 'CB220101',
    email: 'aina@student.uthm.edu.my',
    phone: '0123456789',
    password: 'password123',
    trustScore: 78,
    completedTransactions: 7,
    rating: 4.8,
  ),
  const UserModel(
    id: 'u2',
    name: 'Daniel Lim',
    studentId: 'AI220208',
    email: 'daniel@student.uthm.edu.my',
    phone: '0135551122',
    password: 'password123',
    trustScore: 66,
    completedTransactions: 4,
    rating: 4.6,
  ),
];

final sampleItems = [
  ItemModel(
    id: 'i1',
    sellerId: 'u1',
    title: 'Engineering Mathematics Textbook',
    category: 'Textbooks',
    description:
        'Clean copy with highlighted formulas. Useful for first-year engineering students.',
    price: 35,
    condition: 'Good',
    imageLabel: 'MATH',
    meetupLocation: 'UTHM Library Lobby',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    isFeatured: true,
  ),
  ItemModel(
    id: 'i2',
    sellerId: 'u2',
    title: 'Scientific Calculator FX-570',
    category: 'Electronics',
    description: 'Works perfectly, includes protective case and fresh battery.',
    price: 45,
    condition: 'Like New',
    imageLabel: 'CALC',
    meetupLocation: 'Student Centre',
    createdAt: DateTime.now().subtract(const Duration(hours: 8)),
    isFeatured: true,
  ),
  ItemModel(
    id: 'i3',
    sellerId: 'u1',
    title: 'Desk Lamp for Hostel Room',
    category: 'Room Items',
    description: 'Adjustable warm light lamp. Great for late study sessions.',
    price: 22,
    condition: 'Good',
    imageLabel: 'LAMP',
    meetupLocation: 'Cafeteria Area',
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
];
