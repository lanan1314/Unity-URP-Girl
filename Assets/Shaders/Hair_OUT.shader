Shader "Unlit/Hair_OUT"
{
    Properties
    {
        _BaseMap("BaseMap", 2D) = "white" {}
        _BaseColor("BaseColor", Color) = (1,1,1,1)
        _AlphaMap("Alpha Map", 2D) = "white" {}
        _Cutoff("Alpha Cutoff", Range(0,1)) = 0.5
        _NormalMap("Normal Map", 2D) = "bump"  {}
        _NormalScale("Normal Scale", Range(0, 2)) = 1.0
        
        _Specular("Specular", Color) = (1,1,1,1)
        _SpecIntensity("Specular Intensity", Range(0,10)) = 2
        _Smoothness("Smoothness", Range(0,1)) = 0.5
        _Anisotropy("Anisotropy", Range(-1,1)) = 0
        _BacklightIntensity("Backlight (Translucency)", Range(0,3)) = 0.7
    }
    SubShader
    {
        Tags 
        { 
            "RenderType" = "Transparent" 
            "RenderPipeline" = "UniversalPipeline"
            "Queue"="Transparent"
        }
        LOD 200
        
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        ZWrite Off
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        #include "MyHLSL.hlsl"

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);
        TEXTURE2D(_AlphaMap);
        SAMPLER(sampler_AlphaMap);
        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_NormalMap);
                    
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float4 _AlphaMap_ST;
            float4 _NormalMap_ST;
            float4 _BaseColor;
            float4 _Specular;
            float _NormalScale, _Cutoff, _Anisotropy, _Smoothness, _SpecIntensity, _BacklightIntensity;
        CBUFFER_END
        ENDHLSL
        
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
            };
            
            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float4 tangentWS : TEXCOORD2;
                float3 viewDir : TEXCOORD3;
                float3 positionWS : TEXCOORD4;
                float4 shadowCoord : TEXCOORD5;
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
                o.viewDir = GetWorldSpaceNormalizeViewDir(vertexInputs.positionWS);
                o.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                o.shadowCoord = GetShadowCoord(vertexInputs);
                return o;
            }
            
            half4 frag(Varyings i) : SV_Target
            {
                float4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                float alpha = SAMPLE_TEXTURE2D(_AlphaMap, sampler_AlphaMap, i.uv).r * _Cutoff;
                if (alpha < 0.001) discard;

                float3 baseCol = baseTex.rgb * _BaseColor.rgb;
                float3 viewDir = normalize(i.viewDir);

                float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv), _NormalScale);
                float3x3 tbn = float3x3(
                    i.tangentWS.xyz,
                    cross(i.normalWS, i.tangentWS.xyz) * i.tangentWS.w,
                    i.normalWS
                );
                float3 normalWS = NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, tbn));
                
                // 主光源
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                float3 lightDir = normalize(mainLight.direction);
                float Lcol = mainLight.color * mainLight.distanceAttenuation * mainLight.shadowAttenuation;

                float NdotL = saturate(dot(normalWS, lightDir));
                half3 halfDir = SafeNormalize(lightDir + viewDir);
                half NdotH = saturate(dot(normalWS, halfDir));
                half NdotV = saturate(dot(normalWS, viewDir));
                half VdotH = saturate(dot(viewDir, halfDir));
                float3 F0 = _Specular.rgb * 0.04;
                half roughness = 1.0 - _Smoothness;
                roughness = roughness * roughness;
                
                // 法线分布函数 (GGX)
                float D = DistributionAnisotropic(roughness, lightDir, viewDir, normalWS, i.tangentWS, _Anisotropy);
                half G = GeometrySmith(NdotV, NdotL, roughness);
                float3 F = Fresnel(F0, VdotH);

                float3 spec = BRDF(D, G, F, NdotV, NdotL) * Lcol * NdotL * _SpecIntensity;
                float3 diff = baseCol * NdotL * Lcol * 0.15;

                float back = saturate((1.0 - saturate(dot(lightDir, normalWS))) * _BacklightIntensity);
                float3 backlight = baseCol * back * Lcol;

                float rim = pow(saturate(1.0 - saturate(dot(normalWS, viewDir))), 2.0);
                float3 rimCol = baseCol * rim * 0.5 * _SpecIntensity;
                
                half3 color = diff + spec + backlight + rimCol;
                
                return half4(color, alpha);
            }
            ENDHLSL
        }
    }
}