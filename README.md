# UTHM CampusTrade – Structured Campus Marketplace System

UTHM CampusTrade is a Flutter-based mobile marketplace application developed for Universiti Tun Hussein Onn Malaysia (UTHM) students. The system provides a structured, secure, and trust-driven platform for student-to-student trading activities within a closed campus ecosystem.

The application replaces unorganized trading through messaging apps and social media with a centralized system that supports verified users, structured transactions, real-time communication, and safe meetup coordination.

---

# 🚀 Project Objectives

The main objectives of this project are:

- To develop a structured campus-based marketplace for UTHM students
- To improve trust and accountability in student-to-student trading
- To provide a clear transaction workflow from listing to completion
- To reduce unsafe and uncoordinated physical meetups
- To promote sustainable reuse of items within the campus community

---

# 🧩 Key Features

## 👤 User Authentication
- Firebase Authentication integration
- Secure login and registration system
- Verified user access control

## 🛒 Marketplace System
- Create and browse item listings
- Search and filter items
- View item details with seller information

## 💬 Transaction System
- Structured offer-based workflow
- Accept / Reject transaction handling
- Real-time transaction status tracking
- Transaction history records

## 📍 Meetup Coordination
- Google Maps API integration
- Select safe campus meetup locations
- Coordinate physical exchanges securely

## 💬 Chat System
- Real-time messaging between buyer and seller
- Used for negotiation and coordination

## 📊 User Trust System
- Transaction history tracking
- Basic user reliability visibility

## 🎨 UI/UX Features
- Clean and responsive Flutter UI
- Animations and interactive elements
- User-friendly navigation flow

---

# 🏗️ System Architecture

The application follows a layered architecture:

```
UI Layer (Screens)
        ↓
Provider (State Management)
        ↓
Service Layer (Business Logic)
        ↓
Firebase (Authentication + Firestore)
```

---

# 🧠 State Management

This project uses **Provider** for state management:
- `AuthProvider` → handles authentication state
- `ItemProvider` → manages marketplace items
- `TransactionProvider` → manages transaction workflow

---

# 🔥 Tech Stack

## Frontend
- Flutter
- Dart

## Backend
- Firebase Authentication
- Cloud Firestore

## State Management
- Provider

## External Services
- Google Maps API

---

# 🗄️ Firestore Database Structure

## 👤 Users Collection
```plaintext
users/
  userId/
    name: String
    email: String
    reputation: Number
```

## 🛒 Items Collection
```plaintext
items/
  itemId/
    title: String
    description: String
    price: Number
    sellerId: String
    sellerName: String
    imageUrl: String
    status: "available" | "sold"
    createdAt: Timestamp
```

## 💰 Transactions Collection
```plaintext
transactions/
  transactionId/
    itemId: String
    buyerId: String
    sellerId: String
    status: "pending" | "accepted" | "cancelled" | "completed"
    meetupLocation: String
    lat: Double
    lng: Double
    createdAt: Timestamp
```

---

# 📱 App Screens Overview

## 🔐 Login Page
Entry point for authentication with login and registration options.

## 🏠 Home Page
Displays featured and recent listings with search functionality.

## 📄 Item Details Page
Shows full item information, seller details, and offer button.

## 💬 Chat Page
Real-time communication between buyer and seller.

## 📍 Meetup Page
Allows selection of safe campus meetup locations using Google Maps.

## 📊 Transaction History Page
Tracks user transaction history and status updates.

---

# ⚙️ Installation Guide

## 1. Clone Repository
```bash
git clone https://github.com/YOUR_USERNAME/uthm-campus-trade.git
```

## 2. Install Dependencies
```bash
flutter pub get
```

## 3. Firebase Setup
- Create Firebase project
- Enable Authentication (Email/Password)
- Enable Firestore Database
- Add `google-services.json` to `/android/app`

## 4. Run Application
```bash
flutter run
```

---

# 📦 Requirements

- Flutter SDK (latest stable)
- Android Studio / VS Code
- Android SDK 35+
- Firebase project setup
- Google Maps API Key

---

# 🎯 Expected Outcome

The application is expected to:
- Provide a structured student marketplace system
- Improve trust between buyers and sellers
- Reduce unsafe meetup arrangements
- Increase efficiency of campus trading activities
- Encourage sustainable reuse of items

---

# 👨‍💻 Project Members

- Muhammad Qaid Uqail Bin Khairul Anuar
- Muhammad Danial Bin Shaharuddin
- Ezamirul Syakir Bin Shekh Abdul Halim
- Muhammad Rusydi Bin Md Rahfee
- Hazman Irfan Bin Ahsan
- Aiman Afiq Bin Azman

Faculty of Computer Science and Information Technology  
Universiti Tun Hussein Onn Malaysia (UTHM)

---

# 📄 License

This project is developed for academic purposes under UTHM coursework requirements.

---

# ⭐ Future Improvements

- Payment integration
- Push notifications system
- AI-based item recommendation
- Rating & review system
- Advanced fraud detection system

---

# 🔥 Project Summary

UTHM CampusTrade transforms informal student trading into a structured, secure, and scalable digital marketplace designed specifically for campus environments. It emphasizes trust, safety, and usability while promoting sustainable consumption within the university ecosystem.
