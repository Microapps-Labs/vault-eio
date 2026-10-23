# Local output capture

Captured on 2026-10-23 from base source revision `cf29d62249891484efb2ea3defaa83ca77690713`, with the example and copy changes in this commit.

OCaml 5.3.0, Dune 3.22.2, Yojson 3.0.0. The library and example built with dune build @all. The example uses source_from_map only, not the Vault HTTP path. An unreachable match branch that blocked the Yojson 3 development build was removed, and the package now declares Yojson >=3.0.

The PNG is a browser-rendered transcript of the output saved in output.txt, not a fabricated application UI. Run the included OCaml example with `opam exec -- dune exec examples/demo/main.exe` after setting up the dependencies described in the root README. No credentials or client data appear in the capture.
