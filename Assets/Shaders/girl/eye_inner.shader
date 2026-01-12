Shader "Unlit/eye_inner"
{
    Properties
	{
		_BaseMap("Base (Sclera+Iris)", 2D) = "white" {}
		_NormalMap("Normal", 2D) = "bump" {}
		_MRMap("Mask(R=Metal, G=Rough, B=AO)", 2D) = "white" {}
		
		[Toggle(USE_MRMAP)] _UseMRMap("Use MRMap", Float) = 0
		_Metallic("Metallic", Range(0,1)) = 0
		_Roughness("Roughness", Range(0,1)) = 0.6
		_AO("AO", Range(0,1)) = 1

		_Color("Tint", Color) = (1,1,1,1)
		_NormalScale("Normal Scale", Range(0,2)) = 1

		_IrisCenterUV("Iris Center UV", Vector) = (0.5, 0.5, 0, 0)
		_IrisRadius("Iris Radius", Range(0.05,0.5)) = 0.18
		_PupilRadius("Pupil Radius", Range(0.01, 0.15)) = 0.035
		_PupilScale("Pupil Scale", Range(0.5,1.5)) = 1.0
		_IrisParallax("Iris Parallax", Range(0,0.02)) = 0.004

		_SSSStrength("Subsurface Fake", Range(0,1)) = 0.2
	}
	SubShader
	{
		Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

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
			#pragma multi_compile_fog

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
			TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
			TEXTURE2D(_MRMap); SAMPLER(sampler_MRMap);

			CBUFFER_START(UnityPerMaterial)
				float4 _BaseMap_ST;
				float4 _NormalMap_ST;
				float4 _MRMap_ST;

				float4 _Color;
				float _NormalScale;

				float4 _IrisCenterUV;
				float _IrisRadius;
				float _PupilRadius;
				float _PupilScale;
				float _IrisParallax;

				float _SSSStrength;

				float _UseMRMap;
				float _Metallic;
				float _Roughness;
				float _AO;
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
				float2 uv0        : TEXCOORD4;
				float3 viewDirWS  : TEXCOORD5;
				half  fogCoord    : TEXCOORD6;
				float3 bakedGI    : TEXCOORD7;
				float4 shadowCoord: TEXCOORD8;
			};

			Varyings vert(Attributes IN)
			{
				Varyings OUT;
				VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
				VertexNormalInputs nrmInputs   = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

				OUT.positionCS  = posInputs.positionCS;
				OUT.positionWS  = posInputs.positionWS;
				OUT.normalWS    = nrmInputs.normalWS;
				OUT.tangentWS   = nrmInputs.tangentWS;
				OUT.bitangentWS = nrmInputs.bitangentWS;
				OUT.uv0         = TRANSFORM_TEX(IN.uv, _BaseMap);
				OUT.viewDirWS   = GetWorldSpaceViewDir(OUT.positionWS);
				OUT.fogCoord    = ComputeFogFactor(OUT.positionCS.z);
				OUT.bakedGI     = SampleSH(OUT.normalWS);
				OUT.shadowCoord = TransformWorldToShadowCoord(OUT.positionWS);
				return OUT;
			}

						float3 GetNormalWS(Varyings IN, float2 uv)
			{
				float3 n = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, TRANSFORM_TEX(uv, _NormalMap)), _NormalScale);
				float3x3 tbn = float3x3(IN.tangentWS, IN.bitangentWS, IN.normalWS);
				return normalize(mul(n, tbn));
			}
						
			// Radial remap so pupil radius changes while iris outer rim stays fixed
			float2 PupilWarpUV(float2 uv, float2 center, float irisR, float pupilR0, float pupilScale, float parallax, float3 viewDirWS, float3 normalWS)
			{
				float2 d = uv - center;
				float r = length(d);
				float2 dir = (r > 1e-5) ? d / r : float2(0, 0);

				float rp = min(irisR - 1e-4, max(1e-4, pupilR0 * pupilScale));

				float rNew;
				if (r <= rp)
				{
					// scale inside pupil region
					rNew = r * (pupilR0 / rp);
				}
				else
				{
					// map annulus [rp, irisR] -> [pupilR0, irisR]
					float t = saturate((r - rp) / max(1e-4, (irisR - rp)));
					rNew = lerp(pupilR0, irisR, t);
				}

				float2 uvRemap = center + dir * rNew;

				// subtle view-dependent parallax
				float3 V = normalize(viewDirWS);
				float3 N = normalize(normalWS);
				float vndot = dot(V, N);
				float2 parallaxOffset = (V.xy / max(0.1, V.z + 1e-5)) * parallax * (1 - vndot);

				return uvRemap + parallaxOffset;
			}
						
			float V_SmithGGXCorrelated(float NdotV, float NdotL, float a)
			{
				float a2 = a * a;
				float gv = NdotV * sqrt(NdotL * (1.0 - a2) + a2);
				float gl = NdotL * sqrt(NdotV * (1.0 - a2) + a2);
				return 0.5 / (gv + gl + 1e-5);
			}

			half4 frag(Varyings IN) : SV_Target
			{
				// sample textures and parameters
								float2 irisUV = PupilWarpUV(
					IN.uv0, _IrisCenterUV.xy,
					_IrisRadius, _PupilRadius, _PupilScale,
					_IrisParallax, IN.viewDirWS, IN.normalWS
				);

				float4 baseColTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, irisUV) * _Color;
				float3 baseColor = baseColTex.rgb;

				#ifdef USE_MRMAP
				float3 mr = SAMPLE_TEXTURE2D(_MRMap, sampler_MRMap, IN.uv0).rgb;
				float metallic  = mr.r;
				float roughness = saturate(mr.g);
				float ao        = mr.b;
				#else
				float metallic  = _Metallic;
				float roughness = saturate(_Roughness);
				float ao        = _AO;
				#endif

				float3 N = GetNormalWS(IN, irisUV);
				float3 V = normalize(IN.viewDirWS);
				float NdotV = saturate(dot(N, V));

				// PBR setup
				float3 diffuseColor = baseColor * (1.0 - metallic);
				float3 F0 = lerp(float3(0.04, 0.04, 0.04), baseColor, metallic);
				float a = max(1e-3, roughness * roughness);

				// Ambient (baked GI)
				float3 color = IN.bakedGI * diffuseColor;

				// Main light (with shadows)
				Light mainLight = GetMainLight(IN.shadowCoord);
				{
					float3 L = normalize(mainLight.direction);
					float3 H = normalize(L + V);
					float NdotL = saturate(dot(N, L));
					float NdotH = saturate(dot(N, H));
					float VdotH = saturate(dot(V, H));

					if (NdotL > 1e-4)
					{
						float  D = D_GGX(NdotH, a);
						float  Vis = V_SmithGGXCorrelated(NdotV, NdotL, a);
						float3 F = F_Schlick(F0, VdotH);
						float3 spec = D * Vis * F;

						float3 kd = (1.0 - F) * (1.0 - metallic);
						float3 diff = kd * diffuseColor / PI;

						float att = mainLight.distanceAttenuation * mainLight.shadowAttenuation;
						color += (diff + spec) * mainLight.color * att * NdotL;

						// cheap SSS-ish lift for sclera redness
						float back = saturate(dot(-mainLight.direction, N));
						color += baseColor * _SSSStrength * pow(back, 2.0) * mainLight.color * att * NdotL;
					}
				}

				// Additional lights (no real-time shadows here)
				#ifdef _ADDITIONAL_LIGHTS
				uint lightCount = GetAdditionalLightsCount();
				for (uint i = 0u; i < lightCount; i++)
				{
					Light l = GetAdditionalLight(i, IN.positionWS);
					float3 L = normalize(l.direction);
					float3 H = normalize(L + V);
					float NdotL = saturate(dot(N, L));
					if (NdotL <= 1e-4) continue;

					float NdotH = saturate(dot(N, H));
					float VdotH = saturate(dot(V, H));

					float  D = D_GGX(NdotH, a);
					float  Vis = V_SmithGGXCorrelated(NdotV, NdotL, a);
					float3 F = F_Schlick(F0, VdotH);
					float3 spec = D * Vis * F;

					float3 kd = (1.0 - F) * (1.0 - metallic);
					float3 diff = kd * diffuseColor / PI;

					float att = l.distanceAttenuation; // additional lights have no shadow term by default
					color += (diff + spec) * l.color * att * NdotL;
				}
				#endif

				// AO
				color *= ao;

				// Fog
				color = MixFog(color, IN.fogCoord);

				return float4(color, 1.0);
			}
			ENDHLSL
		}
	}
	Fallback Off
}