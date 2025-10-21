import '../services/embedding_service.dart';
import '../config/app_config.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  print('Starting pet embedding process...');
  AppConfig.logConfig();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final firestore = FirebaseFirestore.instance;
  final embeddingService = EmbeddingService();

  try {
    // Check if embedding server is available
    final isServerHealthy = await embeddingService.isServerHealthy();
    if (!isServerHealthy) {
      print('Warning: Embedding server appears to be unavailable. Some embeddings may fail.');
    }

    final pets = await firestore.collection('pets').get();
    print('Found ${pets.docs.length} pets to process');

    int successCount = 0;
    int failureCount = 0;

    for (final doc in pets.docs) {
      print('\nProcessing pet ${doc.id}...');
      final data = doc.data();
      final desc = data['description'] ?? '';
      final photos = List<String>.from(data['photos'] ?? []);

      String? mainPhotoPath;
      File? tempFile;

      // Download image with proper resource management
      if (photos.isNotEmpty) {
        try {
          final url = photos.first;
          print('Downloading image from: $url');

          final tempDir = Directory.systemTemp;
          tempFile = File('${tempDir.path}/${doc.id}_main.jpg');

          final client = http.Client();
          try {
            final response = await client.get(Uri.parse(url))
                .timeout(Duration(seconds: 30));

            if (response.statusCode == 200) {
              await tempFile.writeAsBytes(response.bodyBytes);
              mainPhotoPath = tempFile.path;
              print('Successfully downloaded image to: $mainPhotoPath');
            } else {
              print('Failed to download image: HTTP ${response.statusCode}');
            }
          } finally {
            client.close();
          }
        } catch (e) {
          print('Failed to download image for pet ${doc.id}: $e');
        }
      }

      try {
        List<double>? descEmbedding;
        List<double>? imgEmbedding;
        bool hasUpdates = false;

        // Get text embedding
        if (desc.isNotEmpty) {
          print('Getting text embedding for description...');
          final result = await embeddingService.getTextEmbedding(desc);
          if (result.isSuccess) {
            descEmbedding = result.embedding;
            print('Successfully got text embedding (${descEmbedding?.length} dimensions)');
            hasUpdates = true;
          } else {
            print('Text embedding failed: ${result.error}');
          }
        }

        // Get image embedding
        if (mainPhotoPath != null && File(mainPhotoPath).existsSync()) {
          print('Getting image embedding...');
          final result = await embeddingService.getImageEmbedding(mainPhotoPath);
          if (result.isSuccess) {
            imgEmbedding = result.embedding;
            print('Successfully got image embedding (${imgEmbedding?.length} dimensions)');
            hasUpdates = true;
          } else {
            print('Image embedding failed: ${result.error}');
          }
        }

        // Update Firestore if we have embeddings
        if (hasUpdates) {
          await doc.reference.update({
            if (descEmbedding != null) 'descEmbedding': descEmbedding,
            if (imgEmbedding != null) 'imgEmbedding': imgEmbedding,
          });
          print('Successfully updated pet ${doc.id} with embeddings');
          successCount++;
        } else {
          print('No embeddings generated for pet ${doc.id}');
          failureCount++;
        }
      } catch (e, stackTrace) {
        print('Failed to process embeddings for pet ${doc.id}: $e');
        if (AppConfig.enableDebugLogging) {
          print('Stack trace: $stackTrace');
        }
        failureCount++;
      } finally {
        // Clean up temporary file
        if (tempFile != null && tempFile.existsSync()) {
          try {
            await tempFile.delete();
          } catch (e) {
            print('Warning: Failed to delete temp file: $e');
          }
        }
      }
    }

    print('\n=== Embedding Process Complete ===');
    print('Successfully processed: $successCount pets');
    print('Failed to process: $failureCount pets');
    print('Total pets: ${pets.docs.length}');

  } catch (e, stackTrace) {
    print('Fatal error in embedding process: $e');
    if (AppConfig.enableDebugLogging) {
      print('Stack trace: $stackTrace');
    }
  } finally {
    embeddingService.dispose();
  }
} 