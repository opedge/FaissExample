//
//  BlurDetector.swift
//  FaissExample
//
//  Created by Oleg Poyaganov on 13/05/2018.
//

import MetalPerformanceShaders
import CoreImage
import UIKit


class BlurDetector {
    private lazy var device: MTLDevice = {
        guard let d = MTLCreateSystemDefaultDevice() else {
            fatalError("Can't create metal device")
        }
        return d
    }()
    
    private lazy var commandQueue: MTLCommandQueue = {
        guard let queue = device.makeCommandQueue() else {
            fatalError("Can't create metal command queue")
        }
        return queue
    }()
    
    private lazy var library: MTLLibrary = {
        guard let l = device.makeDefaultLibrary() else {
            fatalError("Can't create default library")
        }
        return l
    }()
    
    private lazy var computePipelineState: MTLComputePipelineState = {
        guard let kernelFunction = library.makeFunction(name: "grayscale") else {
            fatalError("Can't create grayscale compute function")
        }
        guard let state = try? device.makeComputePipelineState(function: kernelFunction) else {
            fatalError("Can't create compute pipeline state")
        }
        return state
    }()
    
    private lazy var textureCache: CVMetalTextureCache = {
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess else {
            fatalError("Can't create metal texture cache")
        }
        return cache!
    }()
    
    private lazy var laplacian: MPSImageLaplacian = {
        return MPSImageLaplacian(device: device)
    }()
    
    private lazy var statistics: MPSImageStatisticsMeanAndVariance = {
        return MPSImageStatisticsMeanAndVariance(device: device)
    }()
    
    private lazy var statisticsImage: MPSImage = {
        let desc = MPSImageDescriptor(channelFormat: .float32, width: 2, height: 1, featureChannels: 1)
        return MPSImage(device: device, imageDescriptor: desc)
    }()
    
    init() {}
    
    func detectBluryness(on pixelBuffer: CVPixelBuffer) -> Float {
        // create metal texture from pixel buffer
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var maybeTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache,
                                                  pixelBuffer, nil, .bgra8Unorm, width, height, 0, &maybeTexture)
        
        guard let texture = maybeTexture else {
            fatalError("Can't create texture from pixel buffer")
        }
        
        guard let metalTexture = CVMetalTextureGetTexture(texture) else {
            fatalError("Can't create metal texture from pixel buffer")
        }
        
        let image = MPSImage(texture: metalTexture, featureChannels: 3)
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Can't create command buffer")
        }
        
        let tmpDesc = MPSImageDescriptor(
            channelFormat: .float32,
            width: image.width,
            height: image.height,
            featureChannels: 1
        )
        let grayImage = MPSTemporaryImage(commandBuffer: commandBuffer, imageDescriptor: tmpDesc)
        
        // convert image to grayscale
        guard let computeEncoder = commandBuffer.makeComputeCommandEncoder() else {
            fatalError("Can't create compute encoder")
        }
        computeEncoder.setComputePipelineState(computePipelineState)
        computeEncoder.setTexture(image.texture, index: 0)
        computeEncoder.setTexture(grayImage.texture, index: 1)
        let threadgroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadgroupCount = MTLSize(
            width: (image.texture.width + threadgroupSize.width - 1) / threadgroupSize.width,
            height: (image.texture.height + threadgroupSize.height - 1) / threadgroupSize.height,
            depth: 1
        )
        computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
        computeEncoder.endEncoding()
        
        let laplacianImage = MPSTemporaryImage(commandBuffer: commandBuffer, imageDescriptor: tmpDesc)

        // calculate laplacian
        laplacian.encode(commandBuffer: commandBuffer, sourceImage: grayImage, destinationImage: laplacianImage)

        // calculate variance of laplacian
        statistics.encode(commandBuffer: commandBuffer, sourceImage: laplacianImage, destinationImage: statisticsImage)
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        // extract variance from texture
        var variance: Float = 0
        statisticsImage.texture.getBytes(
            &variance,
            bytesPerRow: statisticsImage.texture.width * MemoryLayout<Float>.size,
            from: MTLRegionMake2D(1, 0, 1, 1),
            mipmapLevel: 0
        )
        return variance
    }
}
