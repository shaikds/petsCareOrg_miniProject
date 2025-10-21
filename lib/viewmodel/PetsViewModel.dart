import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:string_similarity/string_similarity.dart';

import '../model/Pet.dart';
import '../services/embedding_service.dart';
import '../services/pet_search_service.dart';
import '../config/app_config.dart';

class PetViewModel extends ChangeNotifier {
  final CollectionReference _petsCollection =
      FirebaseFirestore.instance.collection('pets');
  final _storage = FirebaseStorage.instance;
  late final EmbeddingService _embeddingService;
  late final PetSearchService _searchService;

  List<Pet> _pets = [];
  List<String> photos = [];
  List<Pet> filteredPets = [];
  bool _isLoading = false;

  PetViewModel() {
    _embeddingService = EmbeddingService();
    _searchService = PetSearchService(_embeddingService);
    if (AppConfig.enableDebugLogging) {
      AppConfig.logConfig();
    }
  }

  @override
  void dispose() {
    _embeddingService.dispose();
    super.dispose();
  }

  List<Pet> get pets => _pets.toList();

  bool get isLoading => _isLoading;

  Future<void> createPet(Pet pet) async {
    try {
      _isLoading = true;
      notifyListeners();

      print('=== CREATE PET START ===');
      print('Pet name: ${pet.name}');
      print('Pet object reference: ${pet.hashCode}');
      print('Pet.imgEmbedding state on entry: ${pet.imgEmbedding != null ? "EXISTS (${pet.imgEmbedding?.length} dims)" : "NULL"}');
      if (pet.imgEmbedding != null) {
        print('Pet.imgEmbedding reference on entry: ${pet.imgEmbedding.hashCode}');
      }
      print('Pet.photos count: ${pet.photos.length}');

      // Get embeddings with proper error handling
      List<double>? descEmbedding;
      List<double>? imgEmbedding;

      if (pet.description.trim().isNotEmpty) {
        final descResult = await _embeddingService.getTextEmbedding(pet.description);
        if (descResult.isSuccess) {
          descEmbedding = descResult.embedding;
          if (AppConfig.enableDebugLogging) {
            print('Generated text embedding for pet ${pet.name}');
          }
        } else {
          print('Warning: Failed to generate text embedding: ${descResult.error}');
        }
      }

      // Handle image embedding - prioritize existing embedding from uploadImageToStorage
      print('=== CreatePet Image Embedding Check for ${pet.name} ===');
      print('Pet has existing imgEmbedding: ${pet.imgEmbedding != null}');
      print('Pet has photos: ${pet.photos.isNotEmpty}');
      if (pet.photos.isNotEmpty) {
        print('First photo URL: ${pet.photos[0]}');
      }
      if (pet.imgEmbedding != null) {
        print('Existing embedding dimensions: ${pet.imgEmbedding?.length}');
        print('Existing embedding reference: ${pet.imgEmbedding.hashCode}');
      }

      if (pet.imgEmbedding != null) {
        // Use the existing embedding that was generated from local file in uploadImageToStorage
        imgEmbedding = List<double>.from(pet.imgEmbedding!); // Create a defensive copy
        print('✅ Using existing image embedding for pet ${pet.name} (${imgEmbedding?.length} dimensions)');
        print('Copied embedding reference: ${imgEmbedding.hashCode}');
      } else if (pet.photos.isNotEmpty) {
        // This should NOT happen in normal flow, but keep as fallback
        print('⚠️ WARNING: No existing embedding found, attempting fallback generation from: ${pet.photos[0]}');
        print('⚠️ This likely means the embedding was lost somewhere in the upload process!');

        // Try to generate embedding from Firebase URL (now supported)
        final imgResult = await _embeddingService.getImageEmbedding(pet.photos[0]);
        if (imgResult.isSuccess) {
          imgEmbedding = imgResult.embedding;
          print('✅ Fallback: Successfully generated image embedding from Firebase URL for pet ${pet.name}');
          print('✅ Embedding dimensions: ${imgResult.embedding?.length}');
        } else {
          print('❌ Fallback failed: ${imgResult.error}');
          print('❌ Pet will be created without image embedding');
          // Keep imgEmbedding as null - this will result in a pet without image embedding
        }
      } else {
        print('ℹ️ No image embedding possible - no existing embedding and no photos');
      }

      final petData = pet.toJson();
      if (descEmbedding != null) petData['descEmbedding'] = descEmbedding;
      if (imgEmbedding != null) petData['imgEmbedding'] = imgEmbedding;

      // Additional safety: if we have pet.imgEmbedding but imgEmbedding is null, use pet.imgEmbedding directly
      if (imgEmbedding == null && pet.imgEmbedding != null) {
        print('🔧 SAFETY MEASURE: Using pet.imgEmbedding directly since local imgEmbedding is null');
        petData['imgEmbedding'] = pet.imgEmbedding;
      }

      print('=== Final Pet Data for ${pet.name} ===');
      print('Has descEmbedding: ${petData['descEmbedding'] != null}');
      print('Has imgEmbedding: ${petData['imgEmbedding'] != null}');
      if (petData['imgEmbedding'] != null) {
        print('ImgEmbedding length: ${(petData['imgEmbedding'] as List).length}');
        print('ImgEmbedding reference: ${petData['imgEmbedding'].hashCode}');
      }
      print('Pet.imgEmbedding still exists: ${pet.imgEmbedding != null}');
      if (pet.imgEmbedding != null) {
        print('Pet.imgEmbedding length: ${pet.imgEmbedding?.length}');
        print('Pet.imgEmbedding reference: ${pet.imgEmbedding.hashCode}');
      }

      await _petsCollection.add(petData);
      print('=== PET SUCCESSFULLY SAVED TO FIRESTORE ===');
      print('Pet ${pet.name} saved with ${petData['imgEmbedding'] != null ? "image embedding" : "NO image embedding"}');
      await _fetchPets();
    } catch (e) {
      print('Error creating pet: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> readPets() async {
    await _fetchPets();
  }

  Future<void> _fetchPets() async {
    try {
      _isLoading = true;
      // notifyListeners();

      final querySnapshot = await _petsCollection.get();
      _pets = querySnapshot.docs.map((doc) => Pet.fromJson(doc)).toList();
    } catch (e) {
      print('Error fetching pets: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updatePet(String uid, Pet pet) async {
    try {
      final updateData = pet.toJson();
      updateData.removeWhere((key, value) => value == null);
      await _petsCollection.doc(uid).update(updateData);

      // Update the list of pets after updating the pet
      await _fetchPets();
    } catch (e) {
      // Handle any errors during pet update
      print('Error updating pet: $e');
    }
  }

  Future<void> deletePet(String petId) async {
    try {
      _isLoading = true;
      notifyListeners();

      await _petsCollection.doc(petId).delete();
      await _fetchPets();
    } catch (e) {
      print('Error deleting pet: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> uploadImageToStorage(List<File> imageFiles, Pet pet) async {
    try {
      _isLoading = true;
      notifyListeners();

      final String petName = pet.name + pet.age.toString();

      print('=== UPLOAD IMAGE TO STORAGE START ===');
      print('Pet name: ${pet.name}');
      print('Initial pet.imgEmbedding state: ${pet.imgEmbedding != null ? "EXISTS (${pet.imgEmbedding?.length} dims)" : "NULL"}');
      print('Number of image files: ${imageFiles.length}');

      // Get image embedding for the first local file BEFORE upload
      if (imageFiles.isNotEmpty) {
        print('Processing local file: ${imageFiles[0].path}');

        final imgResult = await _embeddingService.getImageEmbedding(imageFiles[0].path);
        if (imgResult.isSuccess) {
          pet.imgEmbedding = imgResult.embedding;
          print('✅ Generated image embedding before upload for pet ${pet.name}');
          print('Embedding dimensions: ${imgResult.embedding?.length}');
          print('Pet.imgEmbedding reference: ${pet.imgEmbedding.hashCode}');
          print('Pet object reference: ${pet.hashCode}');
          if (AppConfig.enableDebugLogging) {
            print('Embedding preview: ${imgResult.embedding?.take(5)}...');
          }
        } else {
          print('❌ Failed to generate image embedding before upload: ${imgResult.error}');

          // Fallback: retry once after a short delay
          print('🔄 Attempting to retry embedding generation...');
          await Future.delayed(Duration(milliseconds: 1000));

          final retryResult = await _embeddingService.getImageEmbedding(imageFiles[0].path);
          if (retryResult.isSuccess) {
            pet.imgEmbedding = retryResult.embedding;
            print('✅ Retry successful: Generated image embedding for pet ${pet.name}');
            print('Embedding dimensions: ${retryResult.embedding?.length}');
          } else {
            print('❌ Retry also failed: ${retryResult.error}');
            print('⚠️ Pet will be created without image embedding');
            // Continue with the upload process even if embedding fails
          }
        }
      } else {
        print('⚠️ No image files provided for pet ${pet.name}');
      }

      print('=== UPLOADING FILES TO FIREBASE ===');
      for (File file in imageFiles) {
        String storagePath =
            'pet/$petName/${DateTime.now().millisecondsSinceEpoch}.jpg';
        Reference storageReference = _storage.ref().child(storagePath);
        TaskSnapshot snapshot = await storageReference.putFile(file);
        String downloadURL = await snapshot.ref.getDownloadURL();
        pet.photos.add(downloadURL);
        photos.add(downloadURL);
        print('Uploaded file: ${downloadURL}');
      }

      print('=== BEFORE CALLING createPet ===');
      print('Pet name: ${pet.name}');
      print('Pet.imgEmbedding state: ${pet.imgEmbedding != null ? "EXISTS (${pet.imgEmbedding?.length} dims)" : "NULL"}');
      print('Pet.photos count: ${pet.photos.length}');
      print('Pet object reference: ${pet.hashCode}');
      if (pet.imgEmbedding != null) {
        print('Pet.imgEmbedding reference: ${pet.imgEmbedding.hashCode}');
      }

      await createPet(pet);
    } catch (e) {
      print('Error uploading image to Firebase Storage: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Pet>> findTopMatchesByImage(
    List<Pet> pets,
    String userImagePath,
    int topN,
  ) async {
    try {
      _isLoading = true;
      notifyListeners();

      final filters = SearchFilters(
        maxAge: AppConfig.maxAgeLimit,
        minEnergyLevel: AppConfig.minEnergyLevel,
        description: '',
      );

      final result = await _searchService.searchByImage(
        allPets: pets,
        imagePath: userImagePath,
        filters: filters,
        customTopN: topN,
      );

      if (result.isSuccess) {
        filteredPets = result.pets;
        return filteredPets;
      } else {
        print('Image search failed: ${result.error}');
        return [];
      }
    } catch (e) {
      print('Error finding image matches: $e');
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<Pet>> findTopMatches(
    List<Pet> pets,
    bool isMale,
    bool isFemale,
    int maxAge,
    int minEnergyLevel,
    String userDescription, {
    int topN = 3,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      final filters = SearchFilters(
        isMale: isMale,
        isFemale: isFemale,
        maxAge: maxAge,
        minEnergyLevel: minEnergyLevel,
        description: userDescription,
      );

      final result = await _searchService.searchPets(
        allPets: pets,
        filters: filters,
        searchMode: SearchMode.textToText,
        customTopN: topN,
      );

      if (result.isSuccess) {
        filteredPets = result.pets;
        if (AppConfig.enableDebugLogging) {
          print('Found ${filteredPets.length} matching pets');
        }
        return filteredPets;
      } else {
        print('Search failed: ${result.error}');
        return [];
      }
    } catch (e) {
      print('Error finding matches: $e');
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @Deprecated('Use EmbeddingService.cosineSimilarity instead')
  double cosineSimilarity(List<double> a, List<double> b) {
    return EmbeddingService.cosineSimilarity(a, b);
  }

  // Method to calculate the description score between two strings
  int _calculateLevenshteinDistance(String a, String b) {
    if (a.isEmpty || b.isEmpty) return a.length + b.length;

    List<int> previousRow = List.generate(b.length + 1, (i) => i);
    List<int> currentRow = List<int>.filled(b.length + 1, 0);

    for (int i = 1; i <= a.length; i++) {
      currentRow[0] = i;

      for (int j = 1; j <= b.length; j++) {
        int insertCost = currentRow[j - 1] + 1;
        int deleteCost = previousRow[j] + 1;
        int replaceCost = previousRow[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);

        currentRow[j] = [insertCost, deleteCost, replaceCost]
            .reduce((minValue, value) => minValue > value ? value : minValue);
      }

      // Swap the rows
      List<int> temp = previousRow;
      previousRow = currentRow;
      currentRow = temp;
    }

    return previousRow[b.length];
  }

  // Method to calculate the description score between two strings
  int _calculateDescriptionScore(
      String petDescription, String userDescription) {
    // Calculate the Levenshtein distance between the two descriptions
    int distance = _calculateLevenshteinDistance(
        petDescription.toLowerCase(), userDescription.toLowerCase());

    // Calculate the similarity as the inverse of the distance (higher values indicate better matches)
    double similarity = 1 - (distance / petDescription.length);

    // Convert the similarity score to a percentage (0 to 100)
    int score = (similarity * 100).round();

    // Return the score
    return score;
  }

  static bool _hasRunEmbedding = false; // Flag to ensure it runs only once

  Future<void> embedAllPets() async {
    // Only run once per app session
    if (_hasRunEmbedding) {
      print('🔄 Embedding already completed this session. Skipping.');
      return;
    }

    print('🚀 Starting automated pet embedding process...');
    _hasRunEmbedding = true;

    try {
      // Check if embedding server is available
      print('🔍 Checking embedding server health...');
      final isServerHealthy = await _embeddingService.isServerHealthy();
      if (!isServerHealthy) {
        print('❌ WARNING: Embedding server is not available!');
        print('Please make sure the server is running: python embed_server.py');
        _hasRunEmbedding = false; // Reset flag so it can be retried
        return;
      }
      print('✅ Embedding server is healthy and ready');

      // Get all pets from Firestore
      print('📋 Fetching pets from Firestore...');
      final querySnapshot = await _petsCollection.get();
      final petDocs = querySnapshot.docs;

      if (petDocs.isEmpty) {
        print('📋 No pets found in database. Nothing to embed.');
        return;
      }

      print('Found ${petDocs.length} pets to process');

      int successCount = 0;
      int failureCount = 0;
      int skippedCount = 0;
      int textEmbeddingCount = 0;
      int imageEmbeddingCount = 0;

      for (int i = 0; i < petDocs.length; i++) {
        final doc = petDocs[i];
        final petNumber = i + 1;

        try {
          final data = doc.data() as Map<String, dynamic>;
          final petName = data['name'] ?? 'Unknown';
          final desc = data['description'] ?? '';
          final photos = List<String>.from(data['photos'] ?? []);

          // Check if embeddings already exist
          final hasDescEmbedding = data['descEmbedding'] != null;
          final hasImgEmbedding = data['imgEmbedding'] != null;

          print('[$petNumber/${petDocs.length}] Processing: $petName');

          // Skip if already has both embeddings
          if (hasDescEmbedding && hasImgEmbedding) {
            print('  ⏭️ Already has both embeddings - skipping');
            skippedCount++;
            continue;
          }

          List<double>? descEmbedding;
          List<double>? imgEmbedding;
          bool hasUpdates = false;

          // Generate text embedding if needed
          if (!hasDescEmbedding && desc.isNotEmpty) {
            print('  🔤 Generating text embedding...');
            final result = await _embeddingService.getTextEmbedding(desc);
            if (result.isSuccess) {
              descEmbedding = result.embedding;
              textEmbeddingCount++;
              hasUpdates = true;
              print('  ✅ Text embedding: ${descEmbedding?.length} dimensions');
            } else {
              print('  ❌ Text embedding failed: ${result.error}');
            }
          }

          // Generate image embedding if needed
          if (!hasImgEmbedding && photos.isNotEmpty) {
            print('  🖼️ Generating image embedding from URL...');
            final imageUrl = photos.first;

            final result = await _embeddingService.getImageEmbedding(imageUrl);
            if (result.isSuccess) {
              imgEmbedding = result.embedding;
              imageEmbeddingCount++;
              hasUpdates = true;
              print('  ✅ Image embedding: ${imgEmbedding?.length} dimensions');
            } else {
              print('  ❌ Image embedding failed: ${result.error}');
            }
          }

          // Update Firestore if we have new embeddings
          if (hasUpdates) {
            print('  💾 Updating Firestore...');
            final updateData = <String, dynamic>{};
            if (descEmbedding != null) updateData['descEmbedding'] = descEmbedding;
            if (imgEmbedding != null) updateData['imgEmbedding'] = imgEmbedding;

            await doc.reference.update(updateData);
            print('  ✅ Successfully updated pet $petName');
            successCount++;
          } else {
            print('  ⚠️ No new embeddings generated');
            failureCount++;
          }

        } catch (e) {
          print('  ❌ Error processing pet ${doc.id}: $e');
          failureCount++;
        }
      }

      // Final summary
      print('\n🎉 ============= EMBEDDING PROCESS COMPLETE =============');
      print('📊 SUMMARY:');
      print('   ✅ Successfully processed: $successCount pets');
      print('   ❌ Failed to process: $failureCount pets');
      print('   ⏭️ Skipped (already had embeddings): $skippedCount pets');
      print('   📝 Text embeddings generated: $textEmbeddingCount');
      print('   🖼️ Image embeddings generated: $imageEmbeddingCount');
      print('   📋 Total pets in database: ${petDocs.length}');

      final processedTotal = successCount + failureCount;
      if (processedTotal > 0) {
        final successRate = (successCount / processedTotal * 100).round();
        print('   📈 Success rate: $successRate%');
      }

      print('=====================================================');

      // Refresh the pets list to include new embeddings
      await _fetchPets();

    } catch (e) {
      print('💥 Fatal error in embedding process: $e');
      _hasRunEmbedding = false; // Reset flag so it can be retried
    }
  }

  Future<List<Pet>> getTopPet(
    List<Pet> pets,
    bool isMale,
    bool isFemale,
    int maxAge,
    int minEnergyLevel,
    String userDescription, {
    int topN = 3,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      final filters = SearchFilters(
        isMale: isMale,
        isFemale: isFemale,
        maxAge: maxAge,
        minEnergyLevel: minEnergyLevel,
        description: userDescription,
      );

      final result = await _searchService.searchPets(
        allPets: pets,
        filters: filters,
        searchMode: SearchMode.textToImage,
        customTopN: topN,
      );

      if (result.isSuccess) {
        filteredPets = result.pets;
        if (AppConfig.enableDebugLogging) {
          print('Cross-modal search found ${filteredPets.length} matching pets');
        }
        return filteredPets;
      } else {
        print('Cross-modal search failed: ${result.error}');
        return [];
      }
    } catch (e) {
      print('Error in cross-modal search: $e');
      return [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }



  @Deprecated('Replaced by PetSearchService with better error handling')
  Future<List<Pet>> findTopMatchesFallBack(List<Pet> pets, bool isMale, bool isFemale,
      int maxAge, int minEnergyLevel, String userDescription) async {
    print('This fallback method is deprecated. Using PetSearchService instead.');

    final filters = SearchFilters(
      isMale: isMale,
      isFemale: isFemale,
      maxAge: maxAge,
      minEnergyLevel: minEnergyLevel,
      description: userDescription,
    );

    final result = await _searchService.searchPets(
      allPets: pets,
      filters: filters,
      searchMode: SearchMode.textToText,
      customTopN: 2,
    );

    return result.isSuccess ? result.pets : [];
  }

}


