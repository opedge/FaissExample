//
//  Indexer.h
//  FaissExample
//
//  Created by Oleg Poyaganov on 10/05/2018.
//

#import <CoreML/CoreML.h>

@interface SearchResult : NSObject

@property (nonatomic, readonly, nonnull) NSString *identifier;
@property (nonatomic, readonly) float distance;

@end

@interface Indexer : NSObject

@property (nonatomic, readonly) NSInteger numberOfIndexedItems;

// Initialize with PCA matrix for FAISS to transform feature vectors from 1792 to 256 dimensions
- (nonnull instancetype)initWithPCAPath:(nonnull NSString *)pcaPath;

// Add raw feature vector to internal index
- (void)addFeatures:(nonnull MLMultiArray *)features forId:(nonnull NSString *)identifier;

// Search for similar items
- (nonnull NSArray<SearchResult *> *)searchByFeatures:(nonnull MLMultiArray *)features maxResults:(NSInteger)maxResults;

- (void)clear;

// IO
- (void)loadFromPath:(nonnull NSString *)path;
- (void)saveToPath:(nonnull NSString *)path;

@end
