//
//  MetalRender.swift
//  Live555RtspPlayer2
//
//  Created by yumi on 4/4/25.
//

import Foundation
import AVFoundation
import Metal
import MetalKit

class MetalRender: H264DecoderDelegate {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var vertexPositionBuffer: MTLBuffer!
    private var texCoordBuffer: MTLBuffer!
    private var texttureCache: CVMetalTextureCache!
    private var colorParamBuffer: MTLBuffer!
    
    private var metalLayer: CAMetalLayer!
    
    init(view: UIView) {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()
        
        // metal layer setting
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.frame = view.bounds
        view.layer.addSublayer(metalLayer)
        
        // vertex buffer setting
        let vertexPositionData: [Float] = [
            //x, y
            -1.0, -1.0,  // 좌하
             1.0, -1.0,  // 우하
             -1.0, 1.0,  // 좌상
             1.0, 1.0,   // 우상
        ]
        vertexPositionBuffer = device.makeBuffer(bytes: vertexPositionData, length: vertexPositionData.count * MemoryLayout<Float>.size, options: [])!
        
        // texCoordBuffer setting
        let texCoordData: [Float] = [
            0.0, 1.0, // bottom-left
            1.0, 1.0, // bottom-right
            0.0, 0.0, // top-left
            1.0, 0.0 // top-right
        ]
        texCoordBuffer = device.makeBuffer(bytes: texCoordData, length: texCoordData.count * MemoryLayout<Float>.size, options: [])!
        
        // YUV to RGB matrix setting
        let colorMatrix: [Float] = [
            1.164, 1.164, 1.164, 0.0,
            0.0, -0.392, 2.017, 0.0,
            1.596, -0.813, 0.0, 0.0
        ]
        colorParamBuffer = device.makeBuffer(bytes: colorMatrix, length: MemoryLayout<Float>.size * 12, options: [])!
        
        // Metal library / pipeline
        let lib = device.makeDefaultLibrary()!
        let vertexFunc = lib.makeFunction(name: "vertexShader")!
        let fragmentFunc = lib.makeFunction(name: "yuv_rgb")!
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragmentFunc
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        let vertexDescriptior = MTLVertexDescriptor()
        
        // 위치 정보(position: attribute(0))
        vertexDescriptior.attributes[0].format = .float2
        vertexDescriptior.attributes[0].offset = 0
        vertexDescriptior.attributes[0].bufferIndex = 0
        
        // 텍스쳐 좌표 정보(texcoord: attribute(1))
        vertexDescriptior.attributes[1].format = .float2
        vertexDescriptior.attributes[1].offset = 0
        vertexDescriptior.attributes[1].bufferIndex = 1
        
        // 각 버퍼의 stride (vetex/texcoord는 각각 float2 -> 8bytes)
        vertexDescriptior.layouts[0].stride = MemoryLayout<Float>.size * 2
        vertexDescriptior.layouts[1].stride = MemoryLayout<Float>.size * 2
        
        // pipline descriptor에 추가
        desc.vertexDescriptor = vertexDescriptior
        
        pipelineState = try! device.makeRenderPipelineState(descriptor: desc)
        
        // Create CVMetalTextureCache
        CVMetalTextureCacheCreate(nil, nil, device, nil, &texttureCache)
    }
    
    func draw(pixelBuffer: CVPixelBuffer) {
        guard let drawable = metalLayer.nextDrawable() else { return }
        
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        
        // Y plane
        var yTexRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                  texttureCache,
                                                  pixelBuffer,
                                                  nil,
                                                  .r8Unorm,
                                                  width,
                                                  height,
                                                  0,
                                                  &yTexRef)
        
        // UV plane
        var uvTexRef: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                  texttureCache,
                                                  pixelBuffer,
                                                  nil,
                                                  .rg8Unorm,
                                                  width / 2,
                                                  height / 2,
                                                  1,
                                                  &uvTexRef)
        
        guard let yTex = yTexRef, let uvTex = uvTexRef else { return }
        
        let yTexture = CVMetalTextureGetTexture(yTex)!
        let uvTexture = CVMetalTextureGetTexture(uvTex)!
        
        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = drawable.texture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].storeAction = .store
        
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        
        let sampler = device.makeSamplerState(descriptor: samplerDescriptor)!
        
        let cmdBuffer = commandQueue.makeCommandBuffer()!
        let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc)!
        
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexPositionBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(texCoordBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(uvTexture, index: 1)
        encoder.setFragmentBuffer(colorParamBuffer, offset: 0, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 1)
        
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        
        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }
    
    func didDecodeFrame(_ pixelBuffer: CVPixelBuffer) {
        self.draw(pixelBuffer: pixelBuffer)
    }
}





//class MetalRender: NSObject, H264DecoderDelegate {
//    private var device: MTLDevice!
//    private var metalLayer: CAMetalLayer!
//    private var commandQueue: MTLCommandQueue!
//    private var pipelineState: MTLRenderPipelineState!
//    
//    private var vertexBuffer: MTLBuffer!
//    private var coordinateBuffer: MTLBuffer!
//    private var indexBuffer: MTLBuffer!
//    
//    private var yTexture: MTLTexture!
//    private var uvTexture: MTLTexture!
//    
//    weak var viewController: ViewController?
//    
//    func setupMetal() {
//        device = MTLCreateSystemDefaultDevice()
//        metalLayer = CAMetalLayer()
//        metalLayer.device = device
//        metalLayer.pixelFormat = .bgra8Unorm
//        metalLayer.frame = CGRect.init(x: 45.0, y: 500.0, width: 300, height: 200)
//        viewController!.view.layer.addSublayer(metalLayer)
//        
//        commandQueue = device.makeCommandQueue()!
//        
//        // setting shader
//        let library = device.makeDefaultLibrary()
//        let vertexFunction = library?.makeFunction(name: "TextureVertexShader")
//        let fragmentFunction = library?.makeFunction(name: "NV12FragmentShader")
//        
//        let pipelineDescriptor = MTLRenderPipelineDescriptor()
//        pipelineDescriptor.vertexFunction = vertexFunction
//        pipelineDescriptor.fragmentFunction = fragmentFunction
//        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
//        
//        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
//    }
//    
//    func createNV12Texture(from pixelBuffer: CVPixelBuffer) {
//        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
//        
//        
//        let width = CVPixelBufferGetWidth(pixelBuffer)
//        let height = CVPixelBufferGetHeight(pixelBuffer)
//        
//        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
//              let uvPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
//            return
//        }
//        
//        let yDescriptor = MTLTextureDescriptor.texture2DDescriptor(
//            pixelFormat: .r8Unorm,
//            width: width,
//            height: height,
//            mipmapped: false)
//        yTexture = device.makeTexture(descriptor: yDescriptor)
//        yTexture.replace(
//            region: MTLRegionMake2D(0, 0, width, height),
//            mipmapLevel: 0,
//            withBytes: yPlane,
//            bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
//        
//        let uvDescriptor = MTLTextureDescriptor.texture2DDescriptor(
//            pixelFormat: .rg8Unorm,
//            width: width / 2,
//            height: height / 2,
//            mipmapped: false)
//        uvTexture = device.makeTexture(descriptor: uvDescriptor)
//        uvTexture.replace(
//            region: MTLRegionMake2D(0, 0, width / 2, height / 2),
//            mipmapLevel: 0,
//            withBytes: uvPlane,
//            bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1))
//        
//        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
//        
//        render()
//    }
//    
//    func render() {
//        guard let drawable = metalLayer.nextDrawable() else { return }
//        
//        let renderPassDescriptor = MTLRenderPassDescriptor()
//        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
//        renderPassDescriptor.colorAttachments[0].loadAction = .clear
//        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
//        
//        let commandBuffer = commandQueue.makeCommandBuffer()!
//        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
//        encoder.setRenderPipelineState(pipelineState)
//        encoder.setFragmentTexture(yTexture, index: 0)
//        encoder.setFragmentTexture(uvTexture, index: 1)
//        
//        encoder.endEncoding()
//        
//        commandBuffer.present(drawable)
//        commandBuffer.commit()
//        print("metal render finished")
//    }
//    
//    func didDecodeFrame(_ pixelBuffer: CVPixelBuffer) {
//        self.createNV12Texture(from: pixelBuffer)
//    }
//}
