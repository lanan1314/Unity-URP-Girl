Shader "Unlit/skin"
{
    Properties
    {
        _BaseMap("Base Map", 2D) = "white" {}
        _BaseColor("Base Color Tint", Color) = (1.0, 0.9, 0.8, 1)
        _BaseColorStrength("Base Color Strength", Range(0, 3)) = 2.0
        
        _NormalMap("Normal Map", 2D) = "bump" {}
        _NormalStrength("Normal Strength", Range(0, 2)) = 0.5
        
        _SpecularMap("Specular Map", 2D) = "white" {}
        _GlossMap("Gloss Map", 2D) = "white" {}
        _Specular("Specular", Range(0, 1)) = 0.2
        _Roughness("Roughness", Range(0, 1)) = 0.3
        
        _SSSMap("SSS", 2D) = "white" {}
        _SSSColor("SSS Color", Color) = (1, 0.4, 0.4, 1)  // 红色调，模拟血液
        _SSSStrength("SSS Strength", Range(0, 2)) = 0.5
        _SSSRadius("SSS Radius", Range(0, 10)) = 1.0
        
        _AOMap("AO Map", 2D) = "white" {}
        _AOStrength("AO Strength", Range(0, 2)) = 0.5
        
        _Tiling("Tiling", Vector) = (1, 1, 0, 0)
        _Offset("Offset", Vector) = (0, 0, 0, 0)
        _IndirIntensity("IndirIntensity", Range(0, 1)) = 0.8
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
        TEXTURE2D(_NormalMap);
        TEXTURE2D(_SpecularMap);
        TEXTURE2D(_GlossMap);
        TEXTURE2D(_SSSMap);
        TEXTURE2D(_AOMap);
        TEXTURE2D(_BrdfLUT);
        
        SAMPLER(sampler_BaseMap);
        SAMPLER(sampler_NormalMap);
        SAMPLER(sampler_SpecularMap);
        SAMPLER(sampler_GlossMap);
        SAMPLER(sampler_SSSMap);
        SAMPLER(sampler_AOMap);
        SAMPLER(sampler_BrdfLUT);
        
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _BaseColor;
            float _BaseColorStrength;
            float _NormalStrength;
            float _Specular;
            float _Roughness;
            float4 _SSSColor;
            float _SSSStrength;
            float _SSSPower;
            float _AOStrength;
            float4 _Tiling;
            float4 _Offset;
            float _FresnelPower;
            float _FresnelIntensity;
            float _SSSRadius;
            float _IndirIntensity;
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
            
            // 预积分次表面散射函数
            float3 PreIntegratedSkinShading(float3 lightDir, float3 viewDir, float3 normalWS, 
                                          float3 sssMap, float3 sssColor, float sssStrength, float sssRadius)
            {
                float NdotL = saturate(dot(normalWS, lightDir));
                float NdotV = saturate(dot(normalWS, viewDir));
                
                // 计算半角向量
                float3 halfDir = normalize(lightDir + viewDir);
                float NdotH = saturate(dot(normalWS, halfDir));
                
                // 预积分次表面散射的核心计算
                float curvature = 1.0 - NdotV;
                float scatter = pow(curvature, 2.0) * sssStrength;
                
                // 使用SSS贴图控制散射强度
                float sssMask = sssMap.r;
                scatter *= sssMask;
                
                // 计算散射颜色
                float3 sssTerm = sssColor * scatter * sssRadius;
                
                // 添加背向散射效果
                float backScatter = pow(1.0 - NdotL, 3.0) * sssStrength * 0.5;
                sssTerm += sssColor * backScatter * sssMask;
                
                return sssTerm;
            }

            //间接光的菲涅尔
            half IndirF_Function(half NdotV, half F0, half roughness)
            {    
                float Fre = exp2((-5.55473 * NdotV - 6.98316) * NdotV);
                return F0 + Fre * saturate(1 - roughness - F0);
            }
            
            //间接光漫反射
            half3 IndirDiffCal(half3 albedo, float3 normalWS, half NdotV, half roughness)
            {
                half3 ambientCol = SampleSH(normalWS);
                half3 ambient = 0.03 * albedo.rgb;//环境光,取很小的值即可,可省略      
                half3 iblDiffuse = max(half3(0, 0, 0), ambient.rgb + ambientCol);
                half3 Flast = IndirF_Function(NdotV, 0.028, roughness); //引入了粗糙度的菲涅耳项计算高光反射比例 反推出漫反射比例
                half3 kdLast = 1 - Flast;//间接光漫反射系数
                return iblDiffuse * kdLast * albedo.rgb;
            }
            
            half4 frag(Varyings i) : SV_Target
            {
                // 采样贴图
                half3 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                half3 specularMap = SAMPLE_TEXTURE2D(_SpecularMap, sampler_SpecularMap, i.uv);
                half3 glossMap = SAMPLE_TEXTURE2D(_GlossMap, sampler_GlossMap, i.uv);
                half3 sssMap = SAMPLE_TEXTURE2D(_SSSMap, sampler_SSSMap, i.uv);
                half3 aoMap = SAMPLE_TEXTURE2D(_AOMap, sampler_AOMap, i.uv);
                
                // 材质属性
                half3 albedo = baseColor.rgb * _BaseColor.rgb * _BaseColorStrength;
                float3 diffuse = albedo / PI;
                half specular = specularMap.r * _Specular;
                half gloss = glossMap.r;
                half roughness = (1.0 - gloss) * _Roughness;
                half ao = lerp(1.0, aoMap.r, _AOStrength);
                
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
                
                half NdotL = saturate(dot(normalWS, lightDir)) ;
                half3 halfDir = SafeNormalize(lightDir + viewDir);
                half NdotH = saturate(dot(normalWS, halfDir));
                half NdotV = saturate(dot(normalWS, viewDir));
                half VdotH = saturate(dot(viewDir, halfDir));
                half3 F0 = specular;

                // BRDF
                half D = D_GGX_TR(NdotH, roughness);
                half G = GeometrySmith(NdotV, NdotL, roughness);
                float3 F = Fresnel(F0, VdotH);
                
                // 组合BRDF
                half3 specularTerm = BRDF(D, G, F, NdotV, NdotL);
                specularTerm *= lightColor * NdotL;
                half3 diffuseTerm = diffuse * lightColor * NdotL;

                // 预积分次表面散射
                half3 sssTerm = PreIntegratedSkinShading(lightDir, viewDir, normalWS, 
                                                       sssMap, _SSSColor.rgb, _SSSStrength, _SSSRadius);
                sssTerm *= lightColor * NdotL;

                // 环境光照
                // 间接光漫反射
                half3 indirDiffCol = IndirDiffCal(albedo.rgb, normalWS, NdotV, roughness) * ao * _IndirIntensity;

                // 最终颜色合成
                half3 finalColor = (diffuseTerm + specularTerm + sssTerm) * ao + indirDiffCol;
                
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
    
    Fallback "Universal Render Pipeline/Lit"
}