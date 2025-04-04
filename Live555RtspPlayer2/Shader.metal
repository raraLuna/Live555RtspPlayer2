//
//  Shader.metal
//  Live555RtspPlayer2
//
//  Created by yumi on 4/4/25.
//

#include <metal_stdlib>
using namespace metal;

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} RasterizerData;

vertex RasterizerData TextureVertexShader(uint vertexID [[vertex_id]],
                                          constant float2 *vertexArray [[buffer(0)]],
                                          constant float2 *coordinateArray [[ buffer(1)]]) {
    RasterizerData out;
    out.clipSpacePosition = float4(vertexArray[vertexID].x,
                                   -vertexArray[vertexID].y,
                                   0.0,
                                   1.0);
    out.textureCoordinate = coordinateArray[vertexID];
    
    return out;
}

fragment float4 NV12FragmentShader(RasterizerData in [[stage_in]],
                                  texture2d<float, access::sample> yTexture [[texture(0)]],
                                  texture2d<float, access::sample> uvTexture [[texture(1)]]) {
    constexpr sampler s(mag_filter::linear,
                        min_filter::linear,
                        s_address::clamp_to_edge,
                        t_address::clamp_to_edge);
    
    float y = yTexture.sample(s, in.textureCoordinate).r;
    float2 uv = uvTexture.sample(s, in.textureCoordinate).rg;
    
    float u = uv.x - 0.5;
    float v = uv.y - 0.5;
    
    float r = y + 1.402 * v;
    float g = y - 344136 * u - 0.714136 * v;
    float b = y + 1.772 * u;
    
    return float4(r, g, b, 1.0);
}


