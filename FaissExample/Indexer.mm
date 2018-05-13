//
//  Indexer.m
//  FaissExample
//
//  Created by Oleg Poyaganov on 10/05/2018.
//

#import "Indexer.h"

#include <faiss/index_io.h>
#include <faiss/VectorTransform.h>
#include <faiss/IndexFlat.h>

@interface SearchResult()

@property (nonatomic, readwrite, copy, nonnull) NSString *identifier;
@property (nonatomic, readwrite, assign) float distance;

@end

@implementation SearchResult

+ (instancetype)resultWithId:(NSString *)identifier distance:(double)distance {
    const auto result = [[SearchResult alloc] init];
    result.identifier = identifier;
    result.distance = distance;
    return result;
}

@end

@interface Indexer()

@property (nonatomic, strong) NSMutableArray<NSString *> *ids;

@end

@implementation Indexer {
    std::unique_ptr<faiss::VectorTransform> _pca;
    std::unique_ptr<faiss::Index> _index;
}

- (NSInteger)numberOfIndexedItems {
    return _index->ntotal;
}

- (nonnull instancetype)initWithPCAPath:(nonnull NSString *)pcaPath {
    self = [super init];
    if (self) {
        // Load PCA transform from disk
        _pca = std::unique_ptr<faiss::VectorTransform>(faiss::read_VectorTransform(pcaPath.UTF8String));
        assert(_pca->is_trained);
        
        // Create new index which stores feature vectors after PCA transformation is applied
        [self createIndex];
    }
    return self;
}

- (void)createIndex {
    _index = std::make_unique<faiss::IndexFlatL2>(_pca->d_out);
    self.ids = [NSMutableArray new];
}

- (void)addFeatures:(nonnull MLMultiArray *)features forId:(nonnull NSString *)identifier {
    assert(features.dataType == MLMultiArrayDataTypeFloat32);
    assert(features.shape.count == 1);
    assert(features.shape[0].integerValue == _pca->d_in);
    
    const auto transformed = _pca->apply(1, static_cast<const float *>(features.dataPointer));
    _index->add(1, transformed);
    delete [] transformed;
    
    [self.ids addObject:identifier];
}

- (nonnull NSArray<SearchResult *> *)searchByFeatures:(nonnull MLMultiArray *)features maxResults:(NSInteger)maxResults {
    assert(features.dataType == MLMultiArrayDataTypeFloat32);
    assert(features.shape.count == 1);
    assert(features.shape[0].integerValue == _pca->d_in);
    
    const auto transformed = _pca->apply(1, static_cast<const float *>(features.dataPointer));
    
    auto *I = new long[maxResults];
    auto *D = new float[maxResults];
    
    _index->search(1, transformed, maxResults, D, I);
    
    delete [] transformed;
    
    auto results = [NSMutableArray new];
    
    for (auto i = 0; i < maxResults; i++) {
        const auto idx = I[i];
        if (idx == -1) {
            continue;
        }
        const auto distance = D[i];
        const auto identifier = _ids[idx];
        
        [results addObject:[SearchResult resultWithId:identifier distance:distance]];
    }
    
    delete [] I;
    delete [] D;
    
    return results;
}

- (NSString *)idsPathFromIndexPath:(NSString *)path {
    return [path stringByAppendingString:@"_ids"];
}

- (void)loadFromPath:(nonnull NSString *)path {
    _index = std::unique_ptr<faiss::Index>(faiss::read_index(path.UTF8String));
    const auto idsPath = [self idsPathFromIndexPath:path];
    self.ids = [[NSMutableArray alloc] initWithContentsOfFile:idsPath];
}

- (void)saveToPath:(nonnull NSString *)path {
    faiss::write_index(_index.get(), path.UTF8String);
    const auto idsPath = [self idsPathFromIndexPath:path];
    [self.ids writeToFile:idsPath atomically:YES];
}

- (void)clear {
    [self createIndex];
}

@end
