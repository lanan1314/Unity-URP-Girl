Shader "Unlit/hair" 
{
    Properties
    {
        [Header(Base Textures)]
        _HairOuterAlpha("Hair Outer Alpha", 2D) = "white" {}
        _HairInnerAlpha("Hair Inner Alpha", 2D) = "white" {}
        _HairNormal("Hair Normal Map", 2D) = "bump" {}
        
        [Header(Base Colors)]
        _BaseColor("Base Color", Color) = (0.8, 0.7, 0.6, 1.0)
        _ColorVariation("Color Variation", Range(0, 1)) = 0.1
        _ColorBrightness("Color Brightness", Range(0, 2)) = 1.0
        
        [Header(Specular Colors)]
        _PrimaryColor("Primary Specular Color", Color) = (1.0, 0.9, 0.8, 1.0)
        _SecondaryColor("Secondary Specular Color", Color) = (0.6, 0.5, 0.4, 1.0)
        
        [Header(Soft Specular)]
        _Softness("Highlight Softness", Range(0.1, 3.0)) = 1.5
        _EdgeSoftness("Edge Softness", Range(0.1, 2.0)) = 0.8
        _SmoothTransition("Smooth Transition", Range(0, 1)) = 0.7
        
        [Header(Specular Controls)]
        _PrimaryShift("Primary Shift", Range(-4, 4)) = 0.0
        _SecondaryShift("Secondary Shift", Range(-4, 4)) = 0.5
        _specPower("Specular Power", Range(0, 50)) = 20
        _SpecularWidth("Specular Width", Range(0, 1)) = 0.5
        _SpecularScale("Specular Scale", Range(0, 2)) = 0.3
        
        [Header(Enhanced Specular)]
        _SpecularIntensity("Specular Intensity", Range(0, 5)) = 2.0
        _SpecularContrast("Specular Contrast", Range(0, 3)) = 1.5
        _HighlightSharpness("Highlight Sharpness", Range(0, 10)) = 3.0
        
        [Header(Alpha Controls)]
        _AlphaCutoff("Alpha Cutoff", Range(0, 1)) = 0.1
        _AlphaStrength("Alpha Strength", Range(0, 2)) = 1.0
        
        [Header(Normal Controls)]
        _NormalStrength("Normal Strength", Range(0, 2)) = 1.0
        
        [Header(Programmatic Noise)]
        _NoiseScale("Noise Scale", Range(1, 100)) = 20
        _NoiseStrength("Noise Strength", Range(0, 1)) = 0.3
        _NoiseSpeed("Noise Animation Speed", Range(0, 5)) = 0.0
        
        [Header(Advanced Color Controls)]
        _GradientStart("Gradient Start Color", Color) = (0.6, 0.5, 0.4, 1.0)
        _GradientEnd("Gradient End Color", Color) = (0.9, 0.8, 0.7, 1.0)
        _GradientDirection("Gradient Direction", Vector) = (0, 1, 0, 0)
        _GradientStrength("Gradient Strength", Range(0, 1)) = 0.3
        
        [Header(Volume Enhancement)]
        _HairDensity("Hair Density", Range(0.1, 3.0)) = 1.5
        _LayerCount("Layer Count", Range(1, 8)) = 4
        _LayerOffset("Layer Offset", Range(0, 0.1)) = 0.02
        _VolumeNoise("Volume Noise", Range(0, 1)) = 0.3
    }
    
    SubShader
    {
        Tags { 
            "RenderType" = "Transparent" 
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }

        LOD 100
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        TEXTURE2D(_HairOuterAlpha);
        SAMPLER(sampler_HairOuterAlpha);
        TEXTURE2D(_HairInnerAlpha);
        SAMPLER(sampler_HairInnerAlpha);
        TEXTURE2D(_HairNormal);
        SAMPLER(sampler_HairNormal);
        
        CBUFFER_START(UnityPerMaterial)
            float4 _HairOuterAlpha_ST;
            float4 _HairInnerAlpha_ST;
            float4 _HairNormal_ST;
            float4 _BaseColor;
            float _ColorVariation;
            float _ColorBrightness;
            float4 _PrimaryColor;
            float _PrimaryShift;
            float4 _SecondaryColor;
            float _SecondaryShift;
            float _specPower;
            float _SpecularWidth;
            float _SpecularScale;
            float _AlphaCutoff;
            float _AlphaStrength;
            float _NormalStrength;
            float _NoiseScale;
            float _NoiseStrength;
            float _NoiseSpeed;
            float4 _GradientStart;
            float4 _GradientEnd;
            float4 _GradientDirection;
            float _GradientStrength;
            float _SpecularIntensity;
            float _SpecularContrast;
            float _HighlightSharpness;
            float _HairDensity;
            float _LayerCount;
            float _LayerOffset;
            float _VolumeNoise;
            float _Softness;
            float _EdgeSoftness;
            float _SmoothTransition;
        CBUFFER_END 
        ENDHLSL
        
        Pass
        {
            Tags { "LightMode" = "SRPDefaultUnlit" }
            
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Front

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma shader_feature _USE_BASE_TEX
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _LIGHT_LAYERS
            #pragma multi_compile_fog

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;
                float3 tangentWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
                float fogFactor : TEXCOORD5;
            };

            // 程序化噪声函数
            float2 hash22(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
                p3 += dot(p3, p3.yzx+33.33);
                return frac((p3.xx+p3.yz)*p3.zy);
            }

            float noise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                
                float2 u = f*f*(3.0-2.0*f);
                
                return lerp(lerp(dot(hash22(i + float2(0.0,0.0)), f - float2(0.0,0.0)),
                           dot(hash22(i + float2(1.0,0.0)), f - float2(1.0,0.0)), u.x),
                       lerp(dot(hash22(i + float2(0.0,1.0)), f - float2(0.0,0.0)),
                           dot(hash22(i + float2(1.0,1.0)), f - float2(1.0,1.0)), u.x), u.y);
            }

            float fbm(float2 p)
            {
                float value = 0.0;
                float amplitude = 0.5;
                float frequency = 1.0;
                
                for(int i = 0; i < 4; i++)
                {
                    value += amplitude * noise(p * frequency);
                    amplitude *= 0.5;
                    frequency *= 2.0;
                }
                
                return value;
            }

            // 生成程序化基础颜色
            float4 generateBaseColor(float2 uv, float3 worldPos)
            {
                float4 baseColor = _BaseColor;
                
                // 添加颜色变化
                float noiseValue = fbm(uv * 10.0 + _Time.y * 0.1);
                float3 colorVariation = (noiseValue - 0.5) * _ColorVariation;
                baseColor.rgb += colorVariation;
                
                // 添加渐变效果
                float gradientFactor = dot(normalize(worldPos), normalize(_GradientDirection.xyz));
                gradientFactor = (gradientFactor + 1.0) * 0.5; // 转换到0-1范围
                float4 gradientColor = lerp(_GradientStart, _GradientEnd, gradientFactor);
                baseColor = lerp(baseColor, gradientColor, _GradientStrength);
                
                // 应用亮度
                baseColor.rgb *= _ColorBrightness;
                
                return baseColor;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                
                o.positionCS = vertexInput.positionCS;
                o.uv = v.uv;
                o.normalWS = normalInput.normalWS;
                o.tangentWS = normalInput.tangentWS;
                o.bitangentWS = normalInput.bitangentWS;
                o.positionWS = vertexInput.positionWS;
                o.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                
                return o;
            }

            float3 shiftTangent(float3 T, float3 N, float shift)
            {
                return normalize(T + shift * N);
            }

            float hairStrand(float3 T, float3 V, float3 L, float specPower)
            {
                float3 H = normalize(V + L);
                float HdotT = dot(T, H);
                float sinTH = sqrt(1 - HdotT * HdotT);
                
                // 更柔和的方向衰减
                float dirAtten = smoothstep(-_SpecularWidth * _EdgeSoftness, _SpecularWidth * 0.2, HdotT);
                
                // 使用更柔和的各向异性计算
                float softPower = specPower * _HighlightSharpness * _Softness;
                float anisotropic = pow(sinTH, softPower);
                
                // 添加额外的平滑处理
                anisotropic = smoothstep(0.0, 1.0, anisotropic);
                
                // 应用强度和对比度
                float result = dirAtten * anisotropic * _SpecularScale * _SpecularIntensity;
                
                // 更柔和的对比度调整
                result = pow(result, 1.0 / (_SpecularContrast * _SmoothTransition));
                
                return result;
            }

            float4 getAmbientAndDiffuse(float4 lightColor0, float3 N, float3 L, float2 uv, float3 worldPos)
            {
                float4 baseColor;
                
                // 使用程序化生成的颜色
                baseColor = generateBaseColor(uv, worldPos);
                
                float NdotL = saturate(dot(N, L));
                
                // 添加环境光
                float3 ambient = SampleSH(N) * 0.3;
                
                return float4((lightColor0.rgb * baseColor.rgb * NdotL + ambient * baseColor.rgb), baseColor.a);
            }

            float4 getSpecular(float4 primaryColor, float primaryShift,
                   float4 secondaryColor, float secondaryShift,
                   float3 N, float3 T, float3 V, float3 L, float specPower, float2 uv)
            {
                // 减少噪声影响，让高光更清晰
                float2 noiseUV = uv * _NoiseScale * 0.3 + _Time.y * _NoiseSpeed * 0.2;
                float shiftTex = (fbm(noiseUV) - 0.5) * _NoiseStrength * 0.2;
                
                // 结合法线贴图
                float3 normalMap = UnpackNormal(SAMPLE_TEXTURE2D(_HairNormal, sampler_HairNormal, uv));
                float3 adjustedT = normalize(T + normalMap.xyz * _NormalStrength);
                
                // 更柔和的切线偏移
                float3 t1 = shiftTangent(adjustedT, N, primaryShift + shiftTex);
                float3 t2 = shiftTangent(adjustedT, N, secondaryShift + shiftTex);

                float4 specular = float4(0.0, 0.0, 0.0, 0.0);
                
                // 主高光 - 使用更柔和的参数
                float primarySpec = hairStrand(t1, V, L, specPower);
                specular += primaryColor * primarySpec;
                
                // 次高光 - 更柔和的混合
                float secondarySpec = hairStrand(t2, V, L, specPower * 0.9);
                specular += secondaryColor * secondarySpec * 0.8;
                
                // 添加柔和的内部高光
                float3 internalT = shiftTangent(adjustedT, N, (primaryShift + secondaryShift) * 0.5);
                float internalSpec = hairStrand(internalT, V, L, specPower * 0.7);
                specular += primaryColor * internalSpec * 0.2;
                
                // 更温和的亮度增强
                specular.rgb *= 1.2;
                
                // 添加柔和的颜色混合
                specular.rgb = lerp(specular.rgb, specular.rgb * 0.8, _SmoothTransition);
                
                return specular;
            }

            float4 frag(Varyings i) : SV_Target
            {
                // 采样透明度贴图
                float outerAlpha = SAMPLE_TEXTURE2D(_HairOuterAlpha, sampler_HairOuterAlpha, i.uv).r;
                float innerAlpha = SAMPLE_TEXTURE2D(_HairInnerAlpha, sampler_HairInnerAlpha, i.uv).r;
                float3 normalMap = UnpackNormal(SAMPLE_TEXTURE2D(_HairNormal, sampler_HairNormal, i.uv));
                
                // 计算最终透明度 - 增加密度
                float finalAlpha = (outerAlpha + innerAlpha) * 0.5 * _AlphaStrength * _HairDensity;
                clip(finalAlpha - _AlphaCutoff);
                
                // 构建TBN矩阵并应用法线贴图
                float3x3 TBN = float3x3(i.tangentWS, i.bitangentWS, i.normalWS);
                float3 N = normalize(TransformTangentToWorld(normalMap, TBN));
                float3 T = normalize(i.tangentWS);
                float3 B = normalize(i.bitangentWS);
                float3 V = GetWorldSpaceViewDir(i.positionWS);
                float3 L = GetMainLight().direction;
                
                // 计算多层头发效果
                float4 finalColor = float4(0, 0, 0, 0);
                float totalWeight = 0;
                
                // 创建多层头发效果
                for(int layer = 0; layer < _LayerCount; layer++)
                {
                    // 计算当前层的UV偏移
                    float layerOffset = (float(layer) / _LayerCount) * _LayerOffset;
                    float2 layerUV = i.uv + float2(layerOffset, layerOffset * 0.5);
                    
                    // 添加体积噪声
                    float volumeNoise = fbm(layerUV * 15.0 + _Time.y * 0.05) * _VolumeNoise;
                    float layerAlpha = finalAlpha * (1.0 - float(layer) / _LayerCount) * (0.8 + volumeNoise);
                    
                    if(layerAlpha > _AlphaCutoff)
                    {
                        // 计算当前层的光照
                        float4 ambientdiffuse = getAmbientAndDiffuse(_MainLightColor, N, L, layerUV, i.positionWS);
                        float4 specular = getSpecular(_PrimaryColor, _PrimaryShift, 
                                                     _SecondaryColor, _SecondaryShift, N, B, V, L, _specPower, layerUV);
                        
                        // 为不同层添加不同的颜色变化
                        float layerTint = 1.0 - (float(layer) / _LayerCount) * 0.3;
                        ambientdiffuse.rgb *= layerTint;
                        
                        // 累积颜色
                        float layerWeight = layerAlpha;
                        finalColor += (ambientdiffuse + specular) * layerWeight;
                        totalWeight += layerWeight;
                    }
                }
                
                // 归一化颜色
                if(totalWeight > 0)
                {
                    finalColor /= totalWeight;
                }
                
                // 添加深度感
                float depthFactor = 1.0 - saturate(dot(V, N));
                finalColor.rgb *= (1.0 + depthFactor * 0.3);
                
                // 增强体积感的环境光
                float3 volumeAmbient = SampleSH(N) * 0.5;
                finalColor.rgb += volumeAmbient * finalColor.a * 0.4;
                
                finalColor.a = finalAlpha;
                
                // 应用雾效
                finalColor.rgb = MixFog(finalColor.rgb, i.fogFactor);
                
                return finalColor;
            }
            ENDHLSL
        }

        Pass
        {
            Tags { "LightMode" = "UniversalForward" }
            
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma shader_feature _USE_BASE_TEX
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _LIGHT_LAYERS
            #pragma multi_compile_fog

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float4 positionCS : SV_POSITION;
                float3 tangentWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 bitangentWS : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
                float fogFactor : TEXCOORD5;
            };

            // 程序化噪声函数
            float2 hash22(float2 p)
            {
                float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
                p3 += dot(p3, p3.yzx+33.33);
                return frac((p3.xx+p3.yz)*p3.zy);
            }

            float noise(float2 p)
            {
                float2 i = floor(p);
                float2 f = frac(p);
                
                float2 u = f*f*(3.0-2.0*f);
                
                return lerp(lerp(dot(hash22(i + float2(0.0,0.0)), f - float2(0.0,0.0)),
                           dot(hash22(i + float2(1.0,0.0)), f - float2(1.0,0.0)), u.x),
                       lerp(dot(hash22(i + float2(0.0,1.0)), f - float2(0.0,0.0)),
                           dot(hash22(i + float2(1.0,1.0)), f - float2(1.0,1.0)), u.x), u.y);
            }

            float fbm(float2 p)
            {
                float value = 0.0;
                float amplitude = 0.5;
                float frequency = 1.0;
                
                for(int i = 0; i < 4; i++)
                {
                    value += amplitude * noise(p * frequency);
                    amplitude *= 0.5;
                    frequency *= 2.0;
                }
                
                return value;
            }

            // 生成程序化基础颜色
            float4 generateBaseColor(float2 uv, float3 worldPos)
            {
                float4 baseColor = _BaseColor;
                
                // 添加颜色变化
                float noiseValue = fbm(uv * 10.0 + _Time.y * 0.1);
                float3 colorVariation = (noiseValue - 0.5) * _ColorVariation;
                baseColor.rgb += colorVariation;
                
                // 添加渐变效果
                float gradientFactor = dot(normalize(worldPos), normalize(_GradientDirection.xyz));
                gradientFactor = (gradientFactor + 1.0) * 0.5; // 转换到0-1范围
                float4 gradientColor = lerp(_GradientStart, _GradientEnd, gradientFactor);
                baseColor = lerp(baseColor, gradientColor, _GradientStrength);
                
                // 应用亮度
                baseColor.rgb *= _ColorBrightness;
                
                return baseColor;
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                
                VertexPositionInputs vertexInput = GetVertexPositionInputs(v.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                
                o.positionCS = vertexInput.positionCS;
                o.uv = v.uv;
                o.normalWS = normalInput.normalWS;
                o.tangentWS = normalInput.tangentWS;
                o.bitangentWS = normalInput.bitangentWS;
                o.positionWS = vertexInput.positionWS;
                o.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                
                return o;
            }

            float3 shiftTangent(float3 T, float3 N, float shift)
            {
                return normalize(T + shift * N);
            }

            float hairStrand(float3 T, float3 V, float3 L, float specPower)
            {
                float3 H = normalize(V + L);
                float HdotT = dot(T, H);
                float sinTH = sqrt(1 - HdotT * HdotT);
                
                // 更柔和的方向衰减
                float dirAtten = smoothstep(-_SpecularWidth * _EdgeSoftness, _SpecularWidth * 0.2, HdotT);
                
                // 使用更柔和的各向异性计算
                float softPower = specPower * _HighlightSharpness * _Softness;
                float anisotropic = pow(sinTH, softPower);
                
                // 添加额外的平滑处理
                anisotropic = smoothstep(0.0, 1.0, anisotropic);
                
                // 应用强度和对比度
                float result = dirAtten * anisotropic * _SpecularScale * _SpecularIntensity;
                
                // 更柔和的对比度调整
                result = pow(result, 1.0 / (_SpecularContrast * _SmoothTransition));
                
                return result;
            }

            float4 getAmbientAndDiffuse(float4 lightColor0, float3 N, float3 L, float2 uv, float3 worldPos)
            {
                float4 baseColor;
                
                // 使用程序化生成的颜色
                baseColor = generateBaseColor(uv, worldPos);
                
                float NdotL = saturate(dot(N, L));
                
                // 添加环境光
                float3 ambient = SampleSH(N) * 0.3;
                
                return float4((lightColor0.rgb * baseColor.rgb * NdotL + ambient * baseColor.rgb), baseColor.a);
            }

            float4 getSpecular(float4 primaryColor, float primaryShift,
                   float4 secondaryColor, float secondaryShift,
                   float3 N, float3 T, float3 V, float3 L, float specPower, float2 uv)
            {
                // 减少噪声影响，让高光更清晰
                float2 noiseUV = uv * _NoiseScale * 0.3 + _Time.y * _NoiseSpeed * 0.2;
                float shiftTex = (fbm(noiseUV) - 0.5) * _NoiseStrength * 0.2;
                
                // 结合法线贴图
                float3 normalMap = UnpackNormal(SAMPLE_TEXTURE2D(_HairNormal, sampler_HairNormal, uv));
                float3 adjustedT = normalize(T + normalMap.xyz * _NormalStrength);
                
                // 更柔和的切线偏移
                float3 t1 = shiftTangent(adjustedT, N, primaryShift + shiftTex);
                float3 t2 = shiftTangent(adjustedT, N, secondaryShift + shiftTex);

                float4 specular = float4(0.0, 0.0, 0.0, 0.0);
                
                // 主高光 - 使用更柔和的参数
                float primarySpec = hairStrand(t1, V, L, specPower);
                specular += primaryColor * primarySpec;
                
                // 次高光 - 更柔和的混合
                float secondarySpec = hairStrand(t2, V, L, specPower * 0.9);
                specular += secondaryColor * secondarySpec * 0.8;
                
                // 添加柔和的内部高光
                float3 internalT = shiftTangent(adjustedT, N, (primaryShift + secondaryShift) * 0.5);
                float internalSpec = hairStrand(internalT, V, L, specPower * 0.7);
                specular += primaryColor * internalSpec * 0.2;
                
                // 更温和的亮度增强
                specular.rgb *= 1.2;
                
                // 添加柔和的颜色混合
                specular.rgb = lerp(specular.rgb, specular.rgb * 0.8, _SmoothTransition);
                
                return specular;
            }

            float4 frag(Varyings i) : SV_Target
            {
                // 采样透明度贴图
                float outerAlpha = SAMPLE_TEXTURE2D(_HairOuterAlpha, sampler_HairOuterAlpha, i.uv).r;
                float innerAlpha = SAMPLE_TEXTURE2D(_HairInnerAlpha, sampler_HairInnerAlpha, i.uv).r;
                float3 normalMap = UnpackNormal(SAMPLE_TEXTURE2D(_HairNormal, sampler_HairNormal, i.uv));
                
                // 计算最终透明度 - 增加密度
                float finalAlpha = (outerAlpha + innerAlpha) * 0.5 * _AlphaStrength * _HairDensity;
                clip(finalAlpha - _AlphaCutoff);
                
                // 构建TBN矩阵并应用法线贴图
                float3x3 TBN = float3x3(i.tangentWS, i.bitangentWS, i.normalWS);
                float3 N = normalize(TransformTangentToWorld(normalMap, TBN));
                float3 T = normalize(i.tangentWS);
                float3 B = normalize(i.bitangentWS);
                float3 V = GetWorldSpaceViewDir(i.positionWS);
                float3 L = GetMainLight().direction;
                
                // 计算多层头发效果
                float4 finalColor = float4(0, 0, 0, 0);
                float totalWeight = 0;
                
                // 创建多层头发效果
                for(int layer = 0; layer < _LayerCount; layer++)
                {
                    // 计算当前层的UV偏移
                    float layerOffset = (float(layer) / _LayerCount) * _LayerOffset;
                    float2 layerUV = i.uv + float2(layerOffset, layerOffset * 0.5);
                    
                    // 添加体积噪声
                    float volumeNoise = fbm(layerUV * 15.0 + _Time.y * 0.05) * _VolumeNoise;
                    float layerAlpha = finalAlpha * (1.0 - float(layer) / _LayerCount) * (0.8 + volumeNoise);
                    
                    if(layerAlpha > _AlphaCutoff)
                    {
                        // 计算当前层的光照
                        float4 ambientdiffuse = getAmbientAndDiffuse(_MainLightColor, N, L, layerUV, i.positionWS);
                        float4 specular = getSpecular(_PrimaryColor, _PrimaryShift, 
                                                     _SecondaryColor, _SecondaryShift, N, B, V, L, _specPower, layerUV);
                        
                        // 为不同层添加不同的颜色变化
                        float layerTint = 1.0 - (float(layer) / _LayerCount) * 0.3;
                        ambientdiffuse.rgb *= layerTint;
                        
                        // 累积颜色
                        float layerWeight = layerAlpha;
                        finalColor += (ambientdiffuse + specular) * layerWeight;
                        totalWeight += layerWeight;
                    }
                }
                
                // 归一化颜色
                if(totalWeight > 0)
                {
                    finalColor /= totalWeight;
                }
                
                // 添加深度感
                float depthFactor = 1.0 - saturate(dot(V, N));
                finalColor.rgb *= (1.0 + depthFactor * 0.3);
                
                // 增强体积感的环境光
                float3 volumeAmbient = SampleSH(N) * 0.5;
                finalColor.rgb += volumeAmbient * finalColor.a * 0.4;
                
                finalColor.a = finalAlpha;
                
                // 应用雾效
                finalColor.rgb = MixFog(finalColor.rgb, i.fogFactor);
                
                return finalColor;
            }
            ENDHLSL
        }

        // Shadow casting pass
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }
            
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
        
        // Depth only pass for transparency
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }
            
            ZWrite On
            ColorMask 0
            Cull Off

        }
    }
    
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}