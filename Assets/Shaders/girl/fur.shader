Shader "Unlit/fur"
{
    Properties
    {
        _FurMask("Fur Mask (R)", 2D) = "white" {}
        _NormalMap("Normal Map", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Range(0, 2)) = 0.5

        _FurColor("Fur Color", Color) = (1,1,1,1)
        _Intensity("Intensity", Range(0, 2)) = 0.6

        _RimPower("Rim Power", Range(0.5, 8)) = 3.0
        _RimIntensity("Rim Intensity", Range(0, 3)) = 1.2

        _Wrap("Forward Scatter Wrap", Range(0, 1)) = 0.5

        _Tiling("Tiling", Vector) = (1,1,0,0)
        _Offset("Offset", Vector) = (0,0,0,0)
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent+10"
            "RenderPipeline" = "UniversalPipeline"
        }
        Blend One One
        ZWrite Off
        Cull Back

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"

        TEXTURE2D(_FurMask);
        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_FurMask);
        SAMPLER(sampler_NormalMap);

        CBUFFER_START(UnityPerMaterial)
            float4 _FurMask_ST;
            float4 _NormalMap_ST;

            float4 _FurColor;
            float  _Intensity;
            float  _RimPower;
            float  _RimIntensity;
            float  _Wrap;
            float4 _Tiling;
            float4 _Offset;
            float  _NormalStrength;
        CBUFFER_END

        // 包裹漫反射（正面+少量前向散射）
        inline half WrapDiffuse(half3 n, half3 l, half wrap)
        {
            half ndotl = dot(n, l);
            return saturate((ndotl + wrap) / (1 + wrap));
        }
        ENDHLSL

        Pass
        {
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _LIGHTMAP_ON
            #pragma multi_compile _ _DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ _LIGHT_COOKIE
            #pragma multi_compile _ _FORWARD_PLUS

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float4 tangentWS   : TEXCOORD2;
                float3 positionWS  : TEXCOORD3;
                float3 viewDirWS   : TEXCOORD4;
            };

            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                VertexPositionInputs vp = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs   vn = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                o.positionHCS = vp.positionCS;
                o.positionWS  = vp.positionWS;
                o.normalWS    = vn.normalWS;
                o.tangentWS   = float4(vn.tangentWS, input.tangentOS.w);
                o.viewDirWS   = GetWorldSpaceNormalizeViewDir(vp.positionWS);

                o.uv = TRANSFORM_TEX(input.uv, _FurMask) * _Tiling.xy + _Offset.xy;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // TBN 法线
                half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv), _NormalStrength);
                float3x3 TBN = float3x3(i.tangentWS.xyz,
                                        cross(i.normalWS, i.tangentWS.xyz) * i.tangentWS.w,
                                        i.normalWS);
                half3 n = NormalizeNormalPerPixel(TransformTangentToWorld(nTS, TBN));
                half3 v = normalize(i.viewDirWS);

                // 主光
                Light mainLight = GetMainLight();
                half3 l = mainLight.direction;
                half3 Lcol = mainLight.color * mainLight.distanceAttenuation * mainLight.shadowAttenuation;

                // 包裹漫反射（前向散射感）
                half wrapDiff = WrapDiffuse(n, l, _Wrap);

                // 菲涅耳边缘高亮（毫毛在掠射角更亮）
                half NdotV = saturate(dot(n, v));
                half rim = pow(1.0h - NdotV, _RimPower) * _RimIntensity;

                // 轻微各向异性（沿切线方向的高光拉伸）
                half3 h = normalize(l + v);
                half TdotH = dot(normalize(i.tangentWS.xyz), h);
                half aniso = saturate(TdotH * TdotH);

                // 遮罩
                half mask = SAMPLE_TEXTURE2D(_FurMask, sampler_FurMask, i.uv).r;

                // 环境（使用球谐）
                half3 sh = SampleSH(n);

                half3 col =
                    (_FurColor.rgb * (wrapDiff * Lcol + 0.2h * sh)) *
                    (rim * (0.6h + 0.4h * aniso)) *
                    (_Intensity * mask);

                // 叠加型（One One 混合），Alpha 用于体感控制但不写深度
                return half4(col, saturate(_Intensity * mask));
            }
            ENDHLSL
        }

        // 不需要阴影 Pass；毫毛不投射阴影
    }

    Fallback Off
}