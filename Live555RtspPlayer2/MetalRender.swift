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

class MetalRender: NSObject, H264DecoderDelegate {
    private var device: MTLDevice!
    private var metalLayer: CAMetalLayer!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    
    private var vertexBuffer: MTLBuffer!
    private var coordinateBuffer: MTLBuffer!
    private var indexBuffer: MTLBuffer!
    
    private var yTexture: MTLTexture!
    private var uvTexture: MTLTexture!
    
    weak var viewController: ViewController?
    
    func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.frame = CGRect.init(x: 45.0, y: 500.0, width: 300, height: 200)
        viewController!.view.layer.addSublayer(metalLayer)
        
        commandQueue = device.makeCommandQueue()!
        
        // setting shader
        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "TextureVertexShader")
        let fragmentFunction = library?.makeFunction(name: "NV12FragmentShader")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        pipelineState = try! device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    func createNV12Texture(from pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        guard let yPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvPlane = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1) else {
            return
        }
        
        let yDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: width,
            height: height,
            mipmapped: false)
        yTexture = device.makeTexture(descriptor: yDescriptor)
        yTexture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: yPlane,
            bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
        
        let uvDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg8Unorm,
            width: width / 2,
            height: height / 2,
            mipmapped: false)
        uvTexture = device.makeTexture(descriptor: uvDescriptor)
        uvTexture.replace(
            region: MTLRegionMake2D(0, 0, width / 2, height / 2),
            mipmapLevel: 0,
            withBytes: uvPlane,
            bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1))
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        render()
    }
    
    func render() {
        guard let drawable = metalLayer.nextDrawable() else { return }
        
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(yTexture, index: 0)
        encoder.setFragmentTexture(uvTexture, index: 1)
        
        encoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
        print("metal render finished")
    }
    
    func didDecodeFrame(_ pixelBuffer: CVPixelBuffer) {
        self.createNV12Texture(from: pixelBuffer)
    }
}
