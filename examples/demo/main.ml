let () =
  let lookup = Vault_eio.source_from_map [ ("APP_MODE", "demo"); ("PORT", "8080") ] in
  Printf.printf "Vault source lookup with a local synthetic map\n";
  List.iter
    (fun name ->
      Printf.printf "%s: %s\n" name
        (match lookup name with Some value -> value | None -> "<not found>"))
    [ "APP_MODE"; "PORT"; "MISSING" ];
  Printf.printf "No Vault connection or real secrets used.\n"
