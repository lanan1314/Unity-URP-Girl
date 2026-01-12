Shader "Unlit/eye_outer"
{
    Properties
	{
		_NormalMap("Normal Map", 2D) = "bump" {}
		_NormalScale("Normal Scale", Range(0,2)) = 1
		_Smoothness("Smoothness", Range(0,1)) = 0.95
		_SpecColor("Spec Color", Color) = (1,1,1,1)

		_IOR("Index of Refraction", Range(1.0, 1.6)) = 1.336
		_RefractionStrength("Refraction Strength", Range(0, 1)) = 0.08
		_FresnelPower("Fresnel Power", Range(1,8)) = 5
		_Transparency("Base Transparency", Range(0,1)) = 0.02
	}
	SubShader
	{
		Tags { "Queue"="Transparent" "RenderType"="Transparent" "IgnoreProjector"="True" "RenderPipeline"="UniversalPipeline" }
		Blend SrcAlpha OneMinusSrcAlpha
		ZWrite Off
		Cull Back

		Pass
		{
			Name "Forward"
			Tags { "LightMode"="UniversalForward" }

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
			#pragma multi_compile _ _ADDITIONAL_LIGHTS
			#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX
			#pragma multi_compile _ _SHADOWS_SOFT
			#pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
			#pragma multi_compile_fog

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			TEXTURE2D_X(_CameraOpaqueTexture); SAMPLER(sampler_CameraOpaqueTexture);
			TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);

			CBUFFER_START(UnityPerMaterial)
				float4 _NormalMap_ST;
				float _NormalScale;
				float _Smoothness;
				float4 _SpecColor;
				float _IOR;
				float _RefractionStrength;
				float _FresnelPower;
				float _Transparency;
			CBUFFER_END

			struct Attributes
			{
				float4 positionOS : POSITION;
				float3 normalOS   : NORMAL;
				float4 tangentOS  : TANGENT;
				float2 uv         : TEXCOORD0;
			};

			struct Varyings
			{
				float4 positionCS : SV_POSITION;
				float3 positionWS : TEXCOORD0;
				float3 normalWS   : TEXCOORD1;
				float3 tangentWS  : TEXCOORD2;
				float3 bitangentWS: TEXCOORD3;
				float2 uv         : TEXCOORD4;
				float4 screenPos  : TEXCOORD5;
			};

			Varyings vert (Attributes IN)
			{
				Varyings OUT;
				VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
				VertexNormalInputs nrmInputs   = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

				OUT.positionCS = posInputs.positionCS;
				OUT.positionWS = posInputs.positionWS;
				OUT.normalWS   = nrmInputs.normalWS;
				OUT.tangentWS  = nrmInputs.tangentWS;
				OUT.bitangentWS= nrmInputs.bitangentWS;
				OUT.uv         = TRANSFORM_TEX(IN.uv, _NormalMap);
				OUT.screenPos  = ComputeScreenPos(OUT.positionCS);
				return OUT;
			}

			float3 GetNormalWS(Varyings IN)
			{
				float3 n = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv), _NormalScale);
				float3x3 tbn = float3x3(IN.tangentWS, IN.bitangentWS, IN.normalWS);
				return normalize(mul(n, tbn));
			}

			half4 frag (Varyings IN) : SV_Target
			{
				float3 N = GetNormalWS(IN);
				float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));

				// Fresnel for reflectivity/opacity
				float fres = pow(saturate(1 - dot(N, V)), _FresnelPower);

				// Sample background for fake refraction (needs Opaque Texture enabled)
				float2 screenUV = IN.screenPos.xy / IN.screenPos.w;
				// Snell-ish offset along screen based on normal's view-space xy
				float eta = 1.0 / _IOR;
				float3 R = refract(-V, N, eta);
				float2 offset = R.xy * _RefractionStrength;
				float3 refractedCol = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, screenUV + offset).rgb;

				// Simple specular (Blinn-Phong) for sharp corneal highlight
				Light mainLight = GetMainLight();
				float3 L = normalize(mainLight.direction);
				float3 H = normalize(L + V);
				float NdotL = saturate(dot(N, L));
				float spec = pow(saturate(dot(N, H)), lerp(64, 256, _Smoothness)) * NdotL;
				float3 specCol = spec * _SpecColor.rgb * mainLight.color * mainLight.distanceAttenuation;

				// Compose: refracted base + specular; alpha from fresnel + base transparency
				float3 col = refractedCol + specCol;
				float alpha = saturate(_Transparency + fres);

				return float4(col, alpha);
			}
			ENDHLSL
		}
	}
	FallBack Off
}