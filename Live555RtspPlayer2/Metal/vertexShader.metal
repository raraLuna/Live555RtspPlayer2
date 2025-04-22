//
//  vertexShader.metal
//  Live555RtspPlayer2
//
//  Created by yumi on 4/7/25.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 m_Position [[ attribute(0)]];
    float2 m_TexCoord [[ attribute(1)]];
};

struct VertexOut {
    float4 m_Position [[ position ]];
    float2 m_TexCoord [[ user(texturecoord) ]];
};

struct ColorParameters {
    float3x3 yuvToRGB;
};

vertex VertexOut vertexShader(VertexIn in [[ stage_in ]], uint vid [[ vertex_id ]]) {
    VertexOut out;
    out.m_Position = float4(in.m_Position, 0, 1);
    out.m_TexCoord = in.m_TexCoord;
    return out;
}

fragment half4 yuv_rgb(VertexOut inFrag [[ stage_in ]],
                       texture2d<float> lumaTex [[ texture(0) ]],
                       texture2d<float> chromaTex [[ texture(1)]],
                       sampler bilinear [[sampler(1)]],
                       constant ColorParameters *params [[ buffer(0)]]) {
    
    float y = lumaTex.sample(bilinear, inFrag.m_TexCoord).r;
    float2 uv = chromaTex.sample(bilinear, inFrag.m_TexCoord).rg - float2(0.5, 0.5);
    float3 yuv = float3(y, uv);
    float3 rgb = params->yuvToRGB * yuv;
    
    return half4(half3(rgb), half(1.0));
}
