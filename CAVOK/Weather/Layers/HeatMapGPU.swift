//
//  HeatMapGPU.swift
//  CAVOK
//
//  Created by Juho Kolehmainen on 06/10/2016.
//  Copyright © 2016 Juho Kolehmainen. All rights reserved.
//

import Foundation

import Metal

class HeatMapGPU {
    
    private var outTexture: MTLTexture? = nil
    
    init(input: [HeatData], config: WeatherConfig, steps: GridSteps) {
        guard let device = MTLCreateSystemDefaultDevice(),
            let defaultLibrary = device.newDefaultLibrary()
            else { return }
        
        
        let commandQueue = device.makeCommandQueue()
        
        let kernelFunction = defaultLibrary.makeFunction(name: "heatMapShader")
        let pipelineState = try! device.makeComputePipelineState(function: kernelFunction!)
        
        let width = config.width
        let height = config.height

        let outTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        self.outTexture = device.makeTexture(descriptor: outTextureDescriptor)
        
        var arr = input.flatMap { i in [i.x, i.y, i.value] }
        if (arr.isEmpty) {
            return;
        }
        
        let commandBuffer = commandQueue.makeCommandBuffer()
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()
        
        commandEncoder.setComputePipelineState(pipelineState)
        commandEncoder.setTexture(self.outTexture, at: 0)
        
        var radius = config.radius
        commandEncoder.setBytes(&radius, length: MemoryLayout<Int32>.stride, at: 0)
        
        var count = input.count
        commandEncoder.setBytes(&count, length: MemoryLayout<Int32>.stride, at: 1)
        
        let dataBuffer = device.makeBuffer(bytes: &arr, length: MemoryLayout<Int32>.stride * arr.count, options: .storageModeShared)
        commandEncoder.setBuffer(dataBuffer, offset: 0, at: 2)

        var steps = [steps.purple.int4(), steps.red.int4(), steps.orange.int4(), steps.yellow.int4(), steps.green.int4(), steps.blue.int4()].flatMap { $0 }
        let stepsBuffer = device.makeBuffer(bytes: &steps, length: MemoryLayout<Int32>.stride * steps.count, options: .storageModeShared)
        commandEncoder.setBuffer(stepsBuffer, offset: 0, at: 3)
        
        let threadGroupCount = MTLSizeMake(5, 5, 1)
        let threadGroups = MTLSizeMake(width / threadGroupCount.width, height / threadGroupCount.height, 1)
        
        commandEncoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupCount)
        
        commandEncoder.endEncoding()
        commandBuffer.commit()
        
        commandBuffer.waitUntilCompleted()
        
        if let error = commandBuffer.error {
            print("rendering failed with error: \(error) status: \(commandBuffer.status.rawValue)")
        }
    }
    
    func render() -> CGImage? {
        guard let outTexture = outTexture else {
            return nil
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * outTexture.width
        
        var imageBytes = [UInt8](repeating: 0, count: bytesPerRow * outTexture.height)
        let region = MTLRegionMake2D(0, 0, outTexture.width, outTexture.height)
        
        outTexture.getBytes(&imageBytes, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        let providerRef = CGDataProvider(
            data: NSData(bytes: &imageBytes, length: imageBytes.count * MemoryLayout<UInt8>.size)
        )
        
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(width: outTexture.width, height: outTexture.height, bitsPerComponent: 8, bitsPerPixel: 8 * 4, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo, provider: providerRef!, decode: nil, shouldInterpolate: false, intent: CGColorRenderingIntent.defaultIntent)
    }
}