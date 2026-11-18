# Optional posterior Face domain (contract 1.2.0, plugin 1.4.0)

This is an authored framework contract, not an importer, mesh repair or automatic merging feature. It remains an isolated candidate, not a released contract or approved character upgrade.

## Geometry and channels

Face remains one ArrayMesh surface with the existing Face and eye shader identities. Only indexed TRIANGLES are supported. CUSTOM3 must be RGBA_FLOAT, with X exactly 0 for Face or 1 for posterior; YZW must be zero. Both domains must occur. Each triangle belongs wholly to one domain. CUSTOM2 is RGBA_FLOAT; posterior RGB is finite sRGB in [0,1], alpha exactly1. Colors are decoded to linear in the vertex stage. COLOR retains existing visibility semantics; CUSTOM0/CUSTOM1 retain their original meanings. Positions, normals, UVs, tangents and all blend shapes must meet validator requirements. The framework never welds or repairs geometry and never invents morph correspondence.

The default is disabled. Tagged CUSTOM3 and an extra lit tail require explicit opt-in; this reserves a previously unspecified channel and tightens acceptance of old custom-channel assets. Untagged old assets remain on the old path. Contract 1.2.0 / plugin 1.4.0 explicitly reserves this previously unspecified channel. This candidate version is not a deployment or a release approval.

## Pass chain and authored state

Authored chain: Face base -> Face eye -> optional supported Face outline -> exactly one posterior_lit pass. Both base and lit opt in with u_npr_posterior_enabled=true. Lit priority must be0, with no following pass. Every lit shared uniform must have the same resolved value as Face (including shader defaults); divergent author overrides are rejected, not silently dropped. The existing native display preset owns shared material-profile values. Initialization retains the validated duplicated lit instance, reattaches it after the generated outline, then synchronizes shared values from Face. User source material resources are not edited.

Face base, eye stencil, outline and optional shadow overlay exclude posterior vertices. The lit pass excludes Face. The normal display path keeps Face overlay disabled. Patch opaque lighting uses Burley diffuse, roughness0.8 and specular0; it is not an independently configurable replacement material.

## Supported visibility and effects

Alpha must be finite in [0,1]. Fractional alpha requires coverage dither. Continuous non-dither transparency is explicitly unsupported and rejected before initialization; no transparent sorting guarantee is implied. Display-profile setup cannot turn off required fractional coverage. Runtime set_visibility_alpha and set_dissolve bind the same supported lit pass. Direct arbitrary material mutation is outside this contract.

Packed textured surface effects are rejected until patch UV semantics are supported. Current dissolve coverage is supported, but this is not acceptance of all wetness, rain, emission or material features for the posterior domain.

## Verification and limits

Permanent synthetic regression: .ci_script/framework/posterior_contract_regression.gd, no proprietary/user assets. It verifies malformed mesh rejection, domain rules, pass restrictions, shared-parameter rejection, visibility modes and retained lit identity. Run via the standard framework validation runner with the supplied custom engine. Independent model-specific evidence must also verify original Face channels/morphs, whole-character multi-angle lighting, eye and outline exclusion, shadow and ordering, export, and exact native upgrade rollback. Structural compliance never establishes visual improvement or model acceptance.
