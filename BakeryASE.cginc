#define BAKERY_INV_PI        0.31830988618f

sampler2D _RNM0, _RNM1, _RNM2;

void LightmapUV_float(float2 uv, out float2 lightmapUV)
{
	lightmapUV = uv * unity_LightmapST.xy + unity_LightmapST.zw;
}

void DecodeLightmap(float4 lightmap, out float3 result)
{

#ifdef UNITY_LIGHTMAP_FULL_HDR
	float4 decodeInstructions = float4(0.0, 0.0, 0.0, 0.0); // Never used but needed for the interface since it supports gamma lightmaps
#else
#if defined(UNITY_LIGHTMAP_RGBM_ENCODING)
	float4 decodeInstructions = float4(34.493242, 2.2, 0.0, 0.0); // range^2.2 = 5^2.2, gamma = 2.2
#else
	float4 decodeInstructions = float4(2.0, 2.2, 0.0, 0.0); // range = 2.0^2.2 = 4.59
#endif
#endif

	result = DecodeLightmap(lightmap, decodeInstructions);
}

void SampleRNM0_float(float2 lightmapUV, out float3 result)
{
	DecodeLightmap(tex2D(_RNM0, lightmapUV), result);
}

void SampleRNM1_float(float2 lightmapUV, out float3 result)
{
	DecodeLightmap(tex2D(_RNM1, lightmapUV), result);
}

void SampleRNM2_float(float2 lightmapUV, out float3 result)
{
	DecodeLightmap(tex2D(_RNM2, lightmapUV), result);
}

void SampleL1x_float(float2 lightmapUV, out float3 result)
{
	result = tex2D(_RNM0, lightmapUV);
}

void SampleL1y_float(float2 lightmapUV, out float3 result)
{
	result = tex2D(_RNM1, lightmapUV);
}

void SampleL1z_float(float2 lightmapUV, out float3 result)
{
	result = tex2D(_RNM2, lightmapUV);
}

float shEvaluateDiffuseL1Geomerics(float L0, float3 L1, float3 n)
{
	// average energy
	float R0 = L0;

	// avg direction of incoming light
	float3 R1 = 0.5f * L1;

	// directional brightness
	float lenR1 = length(R1);

	// linear angle between normal and direction 0-1
	//float q = 0.5f * (1.0f + dot(R1 / lenR1, n));
	//float q = dot(R1 / lenR1, n) * 0.5 + 0.5;
	float q = dot(normalize(R1), n) * 0.5 + 0.5;

	// power for q
	// lerps from 1 (linear) to 3 (cubic) based on directionality
	float p = 1.0f + 2.0f * lenR1 / R0;

	// dynamic range constant
	// should vary between 4 (highly directional) and 0 (ambient)
	float a = (1.0f - lenR1 / R0) / (1.0f + lenR1 / R0);

	return R0 * (a + (1.0f - a) * (p + 1.0f) * pow(q, p));
}

void BakerySH_float(float3 L0, float3 normalWorld, float2 lightmapUV, out float3 sh)
{
	float3 nL1x = tex2D(_RNM0, lightmapUV) * 2 - 1;
	float3 nL1y = tex2D(_RNM1, lightmapUV) * 2 - 1;
	float3 nL1z = tex2D(_RNM2, lightmapUV) * 2 - 1;
	float3 L1x = nL1x * L0 * 2;
	float3 L1y = nL1y * L0 * 2;
	float3 L1z = nL1z * L0 * 2;

	float lumaL0 = dot(L0, 1);
	float lumaL1x = dot(L1x, 1);
	float lumaL1y = dot(L1y, 1);
	float lumaL1z = dot(L1z, 1);
	float lumaSH = shEvaluateDiffuseL1Geomerics(lumaL0, float3(lumaL1x, lumaL1y, lumaL1z), normalWorld);

	sh = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
	float regularLumaSH = dot(sh, 1);

	sh *= lerp(1, lumaSH / regularLumaSH, saturate(regularLumaSH * 16));
}

// Following two functions are copied from the original Unity standard shader for compatibility
// -----
float SmoothnessToPerceptualRoughness(float smoothness)
{
	return (1 - smoothness);
}
float BakeryPerceptualRoughnessToRoughness(float perceptualRoughness)
{
	return perceptualRoughness * perceptualRoughness;
}
float GGXTerm(half NdotH, half roughness)
{
	half a2 = roughness * roughness;
	half d = (NdotH * a2 - NdotH) * NdotH + 1.0f; // 2 mad
	return BAKERY_INV_PI * a2 / (d * d + 1e-7f); // This function is not intended to be running on Mobile,
											// therefore epsilon is smaller than what can be represented by half
}
// -----

void DirectionalSpecular_float(float2 lightmapUV, float3 normalWorld, float3 viewDir, float smoothness, out float3 color)
{
#ifdef LIGHTMAP_ON
#ifdef DIRLIGHTMAP_COMBINED
	float4 lmColor = SAMPLE_TEXTURE2D(TEXTURE2D_ARGS(unity_Lightmap, samplerunity_Lightmap), lightmapUV);
	float3 lmDir = SAMPLE_TEXTURE2D(TEXTURE2D_ARGS(unity_LightmapInd, samplerunity_Lightmap), lightmapUV) * 2 - 1;
	float3 halfDir = normalize(normalize(lmDir) + viewDir);
	float nh = saturate(dot(normalWorld, halfDir));
	float perceptualRoughness = SmoothnessToPerceptualRoughness(smoothness);
	float roughness = BakeryPerceptualRoughnessToRoughness(perceptualRoughness);
	float spec = GGXTerm(nh, roughness);
	color = lmColor * spec;
	return;
#endif
#endif
	color = 0;
}

void BakerySpecSH_float(float3 L0, float3 normalWorld, float2 lightmapUV, float3 viewDir, float smoothness, out float3 diffuseSH, out float3 specularSH)
{
	float3 nL1x = tex2D(_RNM0, lightmapUV) * 2 - 1;
	float3 nL1y = tex2D(_RNM1, lightmapUV) * 2 - 1;
	float3 nL1z = tex2D(_RNM2, lightmapUV) * 2 - 1;
	float3 L1x = nL1x * L0 * 2;
	float3 L1y = nL1y * L0 * 2;
	float3 L1z = nL1z * L0 * 2;

	float lumaL0 = dot(L0, 1);
	float lumaL1x = dot(L1x, 1);
	float lumaL1y = dot(L1y, 1);
	float lumaL1z = dot(L1z, 1);
	float lumaSH = shEvaluateDiffuseL1Geomerics(lumaL0, float3(lumaL1x, lumaL1y, lumaL1z), normalWorld);

	diffuseSH = L0 + normalWorld.x * L1x + normalWorld.y * L1y + normalWorld.z * L1z;
	float regularLumaSH = dot(diffuseSH, 1);

	diffuseSH *= lerp(1, lumaSH / regularLumaSH, saturate(regularLumaSH * 16));
	diffuseSH = max(diffuseSH, 0.0);

	const float3 lumaConv = float3(0.2125f, 0.7154f, 0.0721f);

	float3 dominantDir = float3(dot(nL1x, lumaConv), dot(nL1y, lumaConv), dot(nL1z, lumaConv));
	float focus = saturate(length(dominantDir));
	float3 halfDir = normalize(normalize(dominantDir) - -viewDir);
	float nh = saturate(dot(normalWorld, halfDir));
	float perceptualRoughness = SmoothnessToPerceptualRoughness(smoothness);
	float roughness = BakeryPerceptualRoughnessToRoughness(perceptualRoughness);
	float spec = GGXTerm(nh, roughness);

	specularSH = L0 + dominantDir.x * L1x + dominantDir.y * L1y + dominantDir.z * L1z;

	specularSH = max(spec * specularSH, 0.0);


	// Directly apply fresnel and smoothness-dependent grazing term
	// TODO: metals

	float nv = 1.0f - saturate(dot(normalWorld, viewDir));
	float nv2 = nv * nv;
	float fresnel = nv * nv2 * nv2;

	float dielectricF0 = 0.04f;
	float grazingTerm = saturate(smoothness + dielectricF0);
	fresnel = lerp(dielectricF0, grazingTerm, fresnel);

	specularSH *= fresnel;
}


