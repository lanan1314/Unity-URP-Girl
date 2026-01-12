Shader "Unlit/eyelash"
{
    Properties
    {
        _MainTex("Eyelash Texture", 2D) = "white" {}
        _Color("Eyelash Color", Color) = (0.1, 0.1, 0.1, 1)
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.4      // 控制透明阈值
        _Smoothness ("Smoothness", Range(0,1)) = 0.2
    }
    SubShader
    {
        Tags 
        { 
            "RenderType" = "TransparentCutout" 
            "Queue" = "AlphaTest"
            "RenderPipeline" = "UniversalPipeline"
        }
        
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite On
        Cull Off
        
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
                    
        CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            float4 _Color;
            float _Cutoff;
            float _Smoothness;
        CBUFFER_END
        ENDHLSL
        
        Pass
        {
            Name "ForwardLit"
            Tags {"LightMode" = "UniversalForward"}
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
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
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
            };
            
            Varyings vert(Attributes input)
            {
                Varyings o = (Varyings)0;
                
                VertexPositionInputs vertexInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.positionHCS = vertexInputs.positionCS;
                o.uv = TRANSFORM_TEX(input.uv, _MainTex);
                o.normalWS = normalInputs.normalWS;
                return o;
            }
            
            half4 frag(Varyings i) : SV_Target
            {
                float alphaTex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).r;   // 取贴图的 R 通道做 Alpha
                if (alphaTex < _Cutoff) discard;           // Alpha裁剪

                float3 normalWS = normalize(i.normalWS);
                float3 viewDirWS = normalize(GetCameraPositionWS() - i.positionWS);

                // 主光源
                Light mainLight = GetMainLight();
                float3 lightDir = normalize(mainLight.direction);
                float3 lightColor = mainLight.color;

                // Lambert 漫反射
                float NdotL = saturate(dot(normalWS, lightDir));
                float3 diffuse = NdotL * lightColor * _Color.rgb;

                // 简单高光
                float3 halfDir = normalize(lightDir + viewDirWS);
                float NdotH = saturate(dot(normalWS, halfDir));
                float3 specular = pow(NdotH, 64) * _Smoothness * lightColor;

                float3 finalColor = diffuse + specular;

                return half4(finalColor, alphaTex * _Color.a);
            }
            ENDHLSL
        }
    }
    
    Fallback "Hidden/Universal Render Pipeline/FallbackError"
}