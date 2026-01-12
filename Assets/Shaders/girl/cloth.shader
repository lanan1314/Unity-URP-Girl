Shader "Unlit/cloth"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color", Color) = (0.1,0.1,0.1,1)
        
        _PatternMap("Pattern Map (cloth_spec_01)", 2D) = "white" {}
        _PatternColor("Pattern Color", Color) = (0.8, 0.4, 0.2, 1)  // 橙色/铜色
        _PatternIntensity("Pattern Intensity", Range(0, 2)) = 1.0
        
        _NormalMap("Normal Map", 2D) = "bump" {}
        _NormalStrength("Normal Scale", Range(0, 2)) = 1.0
        
        _Metallic("Metallic", Range(0, 1)) = 0.3
        _Roughness("Roughness", Range(0, 1)) = 0.4
        
        _AOMap("AO Map", 2D) = "white"  {}
        _AOStrength("AO Strength", Range(0, 2)) = 1.0
        
        _EmissionMap("Emission Map", 2D) = "white" {}
        _EmissionColor("Emission Color", Color) = (1,1,1,1)
        _EmissionIntensity("Emission Intensity", Range(0, 10)) = 5.0
        _EmissionPower("Emission Power", Range(0.1, 5)) = 1.5
        
        _Tiling("Tiling",  Vector) = (1,1,0,0)
        _Offset("Offset", Vector) = (0,0,0,0)
        _FresnelPower("Fresnel Power", Range(0, 10)) = 3.0
        _FresnelIntensity("Fresnel Intensity", Range(0, 1)) = 0.2
    }
    SubShader
    {
        Tags 
        { 
            "RenderType" = "Opaque" 
            "RenderPipeline" = "UniversalPipeline"
            "Queue" = "Geometry"
        }
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl"
        #include "Assets/Shaders/MyHLSL.hlsl"
        
        TEXTURE2D(_BaseMap);
        TEXTURE2D(_PatternMap);
        TEXTURE2D(_NormalMap);
        TEXTURE2D(_AOMap);
        TEXTURE2D(_EmissionMap);
        
        SAMPLER(sampler_BaseMap);
        SAMPLER(sampler_PatternMap);
        SAMPLER(sampler_NormalMap);
        SAMPLER(sampler_AOMap);
        SAMPLER(sampler_EmissionMap);
        
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _BaseColor;
            float4 _PatternColor;
            float _PatternIntensity;
            float _NormalStrength;
            float _Metallic;
            float _Roughness;
            float _AOStrength;
            float4 _EmissionColor;
            float _EmissionIntensity;
            float _EmissionPower;
            float4 _Tiling;
            float4 _Offset;
            float _FresnelPower;
            float _FresnelIntensity;
        CBUFFER_END
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
            #pragma multi_compile _ _LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ _DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ _SHADOWS_SHADOWMASK
            #pragma multi_compile _ _LIGHT_COOKIE
            #pragma multi_compile _ _FORWARD_PLUS
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 lightmapUV : TEXCOORD1;
            };
            
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 tangentWS : TEXCOORD2;
                float2 lightmapUV : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
                float3 viewDir : TEXCOORD5;
            };
            
            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                VertexPositionInputs vertexInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);

                o.positionHCS = vertexInputs.positionCS;
                o.positionWS = vertexInputs.positionWS;
                o.normalWS = normalInputs.normalWS;
                o.tangentWS = float4(normalInputs.tangentWS, input.tangentOS.w);
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap) * _Tiling.xy + _Offset.xy;
                o.lightmapUV = input.lightmapUV;
                o.viewDir = GetWorldSpaceNormalizeViewDir(vertexInputs.positionWS);
                
                return o;
            }
            
            half4 frag(Varyings i) : SV_Target
            {
                // 采样贴图
                half3 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                half3 patternMap = SAMPLE_TEXTURE2D(_PatternMap, sampler_PatternMap, i.uv);
                half3 aoMap = SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, i.uv);
                half3 emissionMap = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, i.uv);
                
                // 材质属性计算
                half3 albedo = baseColor.rgb * _BaseColor.rgb;
                
                // 关键：使用patternMap作为三角形图案！
                half patternMask = patternMap.r;
                
                // 图案颜色混合
                half3 patternColor = _PatternColor.rgb * _PatternIntensity;
                half3 finalAlbedo = lerp(albedo, patternColor, patternMask);
                
                // 金属度和粗糙度 - 从patternMap中提取
                half metallic = patternMap.r * _Metallic;  // 使用图案的红色通道
                half roughness = (1.0 - patternMap.g) * _Roughness;  // 使用图案的绿色通道
                
                half ao = lerp(1.0, aoMap.r, _AOStrength);
                
                // 发光效果
                half3 emission = pow(emissionMap.rgb, _EmissionPower) * _EmissionIntensity * _EmissionColor.rgb;

                // 法线计算
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv), _NormalStrength);
                float3x3 TBN = float3x3(i.tangentWS.xyz,
                                        cross(i.normalWS, i.tangentWS.xyz) * i.tangentWS.w,
                                        i.normalWS);
                half3 normalWS = NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, TBN));
                half3 viewDir = normalize(i.viewDir);

                // 主光源
                Light light = GetMainLight();
                half3 lightDir = light.direction;
                half3 lightColor = light.color * light.distanceAttenuation * light.shadowAttenuation;

                // PBR计算
                half NdotL = saturate(dot(normalWS, lightDir));
                half3 halfDir = SafeNormalize(lightDir + viewDir);
                half NdotV = saturate(dot(normalWS, viewDir));
                half VdotH = saturate(dot(viewDir, halfDir));
                half NdotH = saturate(dot(normalWS, halfDir));

                // BRDF计算
                half D = D_GGX_TR(NdotH, roughness);
                half G = GeometrySmith(NdotV, NdotL, roughness);
                half3 F = Fresnel(lerp(0.04, finalAlbedo, metallic), VdotH);

                half3 specularTerm = BRDF(D, G, F, NdotV, NdotL) * lightColor * NdotL;
                
                // 漫反射计算
                half3 kS = F;
                half3 kD = (1.0 - kS) * (1.0 - metallic);
                half3 diffuseTerm = kD * finalAlbedo * lightColor * NdotL;

                // 菲涅尔效果
                half fresnel = pow(1.0 - NdotV, _FresnelPower) * _FresnelIntensity;
                half3 fresnelColor = lerp(0.04, finalAlbedo, metallic);

                // 最终颜色合成
                half3 finalColor = (diffuseTerm + specularTerm) * ao + emission + fresnel * fresnelColor;
                
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 texcoord : TEXCOORD0;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;
            };

            Varyings ShadowPassVertex(Attributes input)
            {
                Varyings output;
                output.uv = input.texcoord;
                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS = vertexInput.positionCS;
                return output;
            }

            half4 ShadowPassFragment(Varyings input) : SV_TARGET
            {
                return 0;
            }
            ENDHLSL
        }
    }
}