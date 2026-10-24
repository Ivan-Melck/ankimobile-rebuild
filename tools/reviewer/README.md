# Native reviewer assets

The checked-in JavaScript is generated from the pinned public Anki fork and
MathJax 3.2.2 (the version in its lockfile). Native iOS builds use those assets
without Node or a network connection.

To rebuild after changing the adapter or updating the pinned sources:

```sh
npm ci --prefix tools/reviewer --ignore-scripts
npm run --prefix tools/reviewer build
```

`build.mjs` bundles the fork's image-occlusion parsing, geometry and canvas
renderer. The desktop translation transport is replaced by the native viewer's
English missing-image message. Desktop Fabric conversion methods throw an
explicit unsupported-editor error; no Fabric serialization/editor code ships.
Image occlusion authoring remains a separate native UI task.

The setup adapter retains upstream's animation-frame drawing and adds a 250 ms
one-shot fallback for embedded views where frame callbacks stall. It changes
only image-occlusion setup timing; template JavaScript keeps the system API.

The bundled MathJax SVG component supports offline typesetting. Its TeX settings
follow the fork's reviewer (including `noerrors` and `mathtools`); cached LaTeX
images use filenames produced by the shared backend. Generating missing TeX
images is a desktop task.

License texts for bundled dependencies are copied to
`ios/Flashcards/Resources/reviewer-asset-licenses.txt`. The image-occlusion source
and this adapter are covered by the repository's AGPL license and third-party
notices. Runtime validation includes iOS image/audio, sequential playback,
math/chemistry typesetting and image-occlusion mask drawing/reveal fixtures.
