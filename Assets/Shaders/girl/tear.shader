Shader "Unlit/tear"
{
    Properties
    {
        _Color("Tear Tint", Color) = (0.85,0.95,1,1)
        _Alpha("Base Alpha", Range(0,1)) = 0.6
        _SpecColor("Specular Color", Color) = (1,1,1,1)
        _Smoothness("Specular Sharpness", Range(0,1)) = 0.85
        _FresnelPower("Fresnel Power", Range(0.5,8)) = 3
        _FresnelStrength("Fresnel Strength", Range(0,2)) = 1
        _Distortion("Screen Distortion", Range(0,1)) = 0.2
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }

        ZWrite Off
        Cull Back
        Blend SrcAlpha OneMinusSrcAlpha

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _Color;
            half _Alpha;
            half4 _SpecColor;
            half _Smoothness;
            half _FresnelPower;
            half _FresnelStrength;
            half _Distortion;
        CBUFFER_END

        // Scene color for cheap refraction/wet look
        TEXTURE2D_X(_CameraOpaqueTexture);
        SAMPLER(sampler_CameraOpaqueTexture);
        ENDHLSL

        Pass
        {
            Name "Forward"
            Tags{ "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 normalWS    : TEXCOORD0;
                float3 positionWS  : TEXCOORD1;
                float4 screenPos   : TEXCOORD2;
            };

            Varyings vert(Attributes input)
            {
                Varyings o;
                VertexPositionInputs vi = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs   ni = GetVertexNormalInputs(input.normalOS);

                o.positionHCS = vi.positionCS;
                o.positionWS  = vi.positionWS;
                o.normalWS    = NormalizeNormalPerPixel(ni.normalWS);
                o.screenPos   = ComputeScreenPos(o.positionHCS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = normalize(GetWorldSpaceViewDir(i.positionWS));

                // Sample scene color with slight normal-based distortion
                float2 uv = GetNormalizedScreenSpaceUV(i.screenPos);
                float2 offset = N.xy * (_Distortion * 0.02);
                uv += offset;

                half4 sceneCol = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, uv);

                // Main light specular (Blinn-Phong)
                Light mainLight = GetMainLight();
                float3 L = normalize(mainLight.direction);
                float  NdotL = saturate(dot(N, L));
                float3 H = normalize(L + V);

                // Map _Smoothness (0..1) -> shininess (16..512)
                float shininess = lerp(16.0, 512.0, saturate(_Smoothness));
                float spec = pow(saturate(dot(N, H)), shininess) * NdotL;
                float3 specCol = spec * mainLight.color.rgb * _SpecColor.rgb;

                // Fresnel-driven edge wetness
                float fres = pow(1.0 - saturate(dot(N, V)), _FresnelPower) * _FresnelStrength;

                // Final color: keep scene color, add tint on rim and spec highlight
                float3 col = sceneCol.rgb + fres * _Color.rgb + specCol;

                // Alpha: base + fresnel, with a bit of spec contribution
                float specLuma = dot(specCol, float3(0.299, 0.587, 0.114));
                float alpha = saturate(_Alpha * fres + specLuma);

                return half4(col, alpha);
            }
            ENDHLSL
        }
    }
}