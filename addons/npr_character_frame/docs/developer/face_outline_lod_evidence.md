# Face outline base-level coverage evidence

2026-10-17: Existing native Beaver face preview, Godot 4.8-dev Forward+ on llvmpipe. The 733 face geometry was preserved in the 735 diagnostic asset. Both eyes closed, yaw -45°, outline width 0.6 px. A diagnostic material used the same medial control map for both comparisons.

- Implicit fragment texture LOD: thin medial vertical outline remained.
- Explicit fragment LOD 0: that line disappeared in the inspected capture; nose and face silhouette remained.
- Material role=1, control enabled, lip fix disabled.
- The diagnostic rendered magenta outlines to distinguish coverage from face shading. It did not change the mesh.

The change keeps the B>=1.0 predicate, UV transform, bilinear sampler, role guard, and disabled default. CPU source-contract tests cover enabled/disabled, roles 0/1/2, B=0/.5/254/255/1, and explicit LOD0 in both stages. These are not GPU visual acceptance across all poses.

## Retained capture hashes

- `medial_holdout.png`: `cd8358b450f9949c6270992a7f4ef45fb98fd6fd0e708792fdd6f952fcec95d2`
- `medial_lod0.png`: `5490c0c735eb44a8b7f91d594415cd3c3419c6c1778dcf25b93df2937f175781`
- `medial_map.png`: `f23eae4a2fde92f2e93b278e0300414c1468d83053bc1531c860e1ff76232e8d`

## Remaining verification

The existing project pin rejected a modified framework file, as intended. The pinned shader was restored. Full model regression with the delivered package requires an explicit dependency migration; approval is pending. Near/far scale and slight-angle sweeps remain necessary to assess temporal aliasing. No claim of universal artifact removal or final model acceptance is made.
