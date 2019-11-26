Requires an updated (1.7.3) version of Amplify for URP support

Only Specular SH has been created so far, RNM and non-Specular SH to come later.

# Specular

Plug your normal map and smoothness into "Bakery Spec SH", and plug the output Diffuse into "Override Baked GI" (you'll need to enable this under "Additional Options" on your HDRP/URP template) and Specular into the Emissive.

Currently does not work with the Standard ASE template.
