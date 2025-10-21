# 🐾 PetCare App - AI-Powered Pet Adoption Platform

A comprehensive Flutter app designed for small pet care organizations to manage adoptions with AI-powered recommendations. Built with **MVVM architecture** and **CLIP embeddings** for intelligent pet matching.

## ✨ Features

- **Smart Pet Matching**: AI-powered semantic search using CLIP embeddings
- **Dual Search Modes**: Text-to-text and text-to-image similarity matching
- **Pet Management**: Complete CRUD operations for pet profiles
- **User Authentication**: Firebase-based secure login system
- **Appointment Scheduling**: Book visits with pet managers
- **Image Analysis**: Automatic pet photo analysis and embedding generation
- **Multilingual Support**: Hebrew interface for Israeli organizations

## 🚀 Quick Start

### Prerequisites

- Flutter SDK (>= 2.19.4)
- Python 3.8+ with pip
- Firebase project setup
- Node.js (for the embedding server dependencies)

### 1. Clone the Repository

```bash
git clone <repository-url>
cd PetCare-Org-App-main
```

### 2. Set Up the Flutter App

```bash
# Install Flutter dependencies
flutter pub get

# Configure Firebase (follow Firebase setup guide)
# Add your firebase_options.dart and google-services.json/GoogleService-Info.plist
```

### 3. Set Up the AI Embedding Server

```bash
# Install Python dependencies
pip install fastapi uvicorn torch clip-by-openai pillow

# Install Node.js dependencies (if needed)
npm install
```

### 4. Configure Environment Variables

Copy the `.env` file and customize for your setup:

```bash
# For Android emulator
EMBEDDING_SERVER_HOST=10.0.2.2

# For iOS simulator/desktop
EMBEDDING_SERVER_HOST=127.0.0.1

# For physical device (use your computer's IP)
EMBEDDING_SERVER_HOST=192.168.1.XXX
```

### 5. Start the Embedding Server

```bash
# Start the Python embedding server
python embed_server.py
```

The server will start on `http://localhost:8000` by default.

### 6. Run the App

```bash
# Run on device/emulator
flutter run

# For debug mode with logging
flutter run --dart-define=ENABLE_DEBUG_LOGGING=true
```

## 🤖 AI Features

### Smart Pet Recommendation System

The app uses OpenAI's CLIP model to understand both text descriptions and images:

1. **Text-to-Text Matching**: Compares user preferences with pet descriptions
2. **Text-to-Image Matching**: Finds pets whose photos match textual descriptions
3. **Image-to-Image Matching**: Upload a photo to find visually similar pets

### Embedding Generation

To generate embeddings for existing pets:

```bash
flutter run lib/scripts/embed_all_pets.dart
```

## 📱 Usage Guide

### For Pet Organizations

1. **Add New Pets**:
   - Upload photos and descriptions
   - System automatically generates AI embeddings
   - Set pet attributes (age, energy level, size)

2. **Manage Adoptions**:
   - Track application status
   - Schedule appointments
   - Update pet availability

### For Adopters

1. **Smart Search**:
   - Describe your ideal pet
   - Choose search mode (text or visual)
   - Get top 3 AI-recommended matches

2. **Book Appointments**:
   - Schedule visits with pet managers
   - Get detailed pet information

## 🛠️ Technical Architecture

### Core Services

- **EmbeddingService**: Handles AI embedding generation and similarity calculations
- **PetSearchService**: Implements smart search algorithms with fallback mechanisms
- **AppConfig**: Centralized configuration management

### Data Flow

```
User Input → SearchFilters → PetSearchService → EmbeddingService → CLIP Model
                                ↓
Results ← Similarity Ranking ← Embedding Comparison ← Vector Database
```

### Error Handling

- Automatic retry mechanisms for embedding generation
- Graceful fallback to text-based search when AI is unavailable
- Comprehensive logging for debugging

## 🐛 Troubleshooting

### Common Issues

**Embedding Server Not Responding**:
```bash
# Check if server is running
curl http://localhost:8000/health

# Restart the server
python embed_server.py
```

**No Search Results**:
- Ensure pets have embeddings generated
- Check network connectivity to embedding server
- Try enabling fallback mode

**Android Emulator Issues**:
- Use `10.0.2.2` as the embedding server host
- Enable network access in emulator settings

**Firebase Connection Issues**:
- Verify firebase_options.dart is properly configured
- Check internet connectivity
- Ensure Firebase project has proper authentication setup

### Debug Mode

Enable detailed logging:

```bash
flutter run --dart-define=ENABLE_DEBUG_LOGGING=true
```

## 📊 Performance Optimization

### Embedding Caching
- Embeddings are stored in Firestore for quick retrieval
- Generated once per pet/photo and reused

### Search Optimization
- Basic attribute filtering before AI processing
- Efficient similarity calculations using optimized vector operations

## 🤝 Contributing

This project is designed for small non-profit organizations with limited technical resources. Contributions should focus on:

- Simplifying deployment and setup
- Improving AI accuracy and speed
- Adding documentation and user guides
- Reducing server requirements

## 📜 License

Built for non-profit pet care organizations. Please ensure compliance with your local regulations regarding pet adoption and data handling.

## 💡 For Small Organizations

This app is specifically designed for organizations that:
- ✅ Want AI capabilities without expensive infrastructure
- ✅ Need an easy-to-deploy solution
- ✅ Have limited technical expertise
- ✅ Want to improve adoption success rates

### Low-Cost Deployment Options

1. **Local Setup**: Run embedding server on a volunteer's computer
2. **Cloud Deployment**: Use services like Railway, Heroku, or Google Cloud Run
3. **Hybrid Approach**: Firebase for data, simple VPS for AI processing

## 🆘 Support

For organizations needing help with deployment:

1. Check the troubleshooting section above
2. Ensure all prerequisites are met
3. Contact the development team with detailed error logs
4. Consider simplified deployment options for your technical level

---

**Made with ❤️ for pet rescue organizations worldwide**



