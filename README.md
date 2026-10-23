# vault-eio

Read a Vault secret response into a string lookup function for an OCaml Eio
application. The library can also build the same lookup from an in-memory map.

![Looking up synthetic configuration values from a local map](docs/demo/lookup.png)

The example uses only a local map. It does not connect to Vault or show real
secrets. See [capture details](docs/demo/README.md).

## Build and try the example

Use an OCaml 5.2 or later opam switch and Dune 3.22 or later:

```sh
git clone https://github.com/Microapps-Labs/vault-eio.git
cd vault-eio
opam install . --deps-only
opam exec -- dune exec examples/demo/main.exe
```

`Vault_eio.source_from_map` returns a function of type
`string -> string option`. Looking up an unknown name returns `None`.

## Read from Vault

`Vault_eio.source ~sw ~net config ()` fetches the configured endpoint and returns
a lookup function. The configuration contains `addr`, `token` and `path`.
The request uses the `X-Vault-Token` header and adds a `v1/` path prefix when
needed. Provide the KV-v2 data path, such as `secret/data/app`, rather than
assuming the library discovers the mount type.

The decoder accepts a nested `data.data` object or a bare object. It converts
scalar values to strings and rejects nested objects or arrays as configuration
values. It does not implement Vault login, token renewal, secret rotation or an
environment-variable exporter. Calling the lookup does not change `Sys.getenv`.

The [public interface](lib/vault_eio.mli) lists configuration and typed errors.
The local-map capture does not test Vault authentication or network retrieval.

The package metadata declares MIT. This repository has no standalone license file.
