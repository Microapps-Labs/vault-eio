open Result

module Error = struct
  type t =
    [ `Missing_vault_configuration of string
    | `Vault_http_error of int * string
    | `Vault_json_error of string
    | `Vault_network_error of string
    | `Invalid_secret_response of string ]
end

type error = Error.t

type source = string -> string option

type config = {
  addr : string;
  token : string;
  path : string;
}

type response = { status : int; body : string }

type t = { client : Cohttp_eio.Client.t }

let ( let* ) = bind

let error_to_string = function
  | `Missing_vault_configuration message ->
      "missing vault configuration: " ^ message
  | `Vault_http_error (status, body) ->
      Printf.sprintf "vault HTTP error %d: %s" status body
  | `Vault_json_error message -> "vault JSON error: " ^ message
  | `Vault_network_error message -> "vault network error: " ^ message
  | `Invalid_secret_response message -> "invalid vault response: " ^ message

let trim_prefix_slash value =
  let rec loop i =
    if i < String.length value && value.[i] = '/' then loop (i + 1) else i
  in
  String.sub value (loop 0) (String.length value - loop 0)

let trim_suffix_slash value =
  let rec loop i =
    if i > 0 && value.[i - 1] = '/' then loop (i - 1) else i
  in
  let i = loop (String.length value) in
  String.sub value 0 i

let normalize_path path =
  let path = trim_prefix_slash (String.trim path) in
  if path = "" then ""
  else if String.starts_with ~prefix:"v1/" path then path
  else "v1/" ^ path

let secret_endpoint ~addr ~path =
  Printf.sprintf "%s/%s" (trim_suffix_slash (String.trim addr))
    (normalize_path path)

let as_assoc json =
  match json with
  | `Assoc fields -> Ok fields
  | _ -> Error (`Invalid_secret_response "vault payload is not a JSON object")

let decode_payload json =
  let* top = as_assoc json in
  match List.assoc_opt "data" top with
  | None -> as_assoc json
  | Some (`Assoc nested) -> (
      match List.assoc_opt "data" nested with
      | Some (`Assoc inner) -> Ok inner
      | _ -> Error (`Invalid_secret_response "vault payload data.data is not an object"))
  | Some _ ->
      Error
        (`Invalid_secret_response
          "vault payload data field is invalid: expected nested map")

let value_to_string = function
  | `String value -> Ok value
  | `Bool value -> Ok (if value then "true" else "false")
  | `Int value -> Ok (string_of_int value)
  | `Float value -> Ok (string_of_float value)
  | `Intlit value -> Ok value
  | `Null -> Ok ""
  | `Assoc _ -> Error "cannot use JSON object as environment value"
  | `List _ -> Error "cannot use JSON array as environment value"

let as_source entries =
  let table = Hashtbl.create (List.length entries) in
  List.iter (fun (name, value) -> Hashtbl.replace table name value) entries;
  fun key -> Hashtbl.find_opt table key

let https_connector =
  let authenticator = lazy (Ca_certs.authenticator ()) in
  let tls_config =
    lazy
      (match Lazy.force authenticator with
      | Ok authenticator -> (
          match Tls.Config.client ~authenticator () with
          | Ok config -> Ok config
          | Error (`Msg message) -> Error message)
      | Error (`Msg message) -> Error message)
  in
  fun uri raw ->
    let host =
      Uri.host uri |> Option.map (fun host_name ->
          Domain_name.(host_exn (of_string_exn host_name)))
    in
    match Lazy.force tls_config with
    | Ok config -> Tls_eio.client_of_flow ?host config raw
    | Error message -> raise (Failure ("TLS setup failed: " ^ message))

let create ~net = { client = Cohttp_eio.Client.make ~https:(Some https_connector) net }

let read_body ?(max_size = 20_000_000) body =
  Eio.Buf_read.(parse_exn take_all) body ~max_size

let call ?(max_size = 20_000_000) ~sw ~headers { client } uri =
  try
    let response, body = Cohttp_eio.Client.call client ~sw ?headers `GET uri in
    let status = Cohttp.Response.status response |> Cohttp.Code.code_of_status in
    let body = read_body ~max_size body in
    Ok { status; body }
  with exn -> Error (`Network (Printexc.to_string exn))

let get ~sw ~headers uri t =
  call ~max_size:20_000_000 ~sw ~headers t uri

let parse_json body =
  try Ok (Yojson.Safe.from_string body) with
  | Yojson.Json_error message -> Error (`Json message)

let decode_payload_error = function
  | `Invalid_secret_response message -> `Invalid_secret_response message
  | `Json message -> `Vault_json_error message
  | `Http (status, body) -> `Vault_http_error (status, body)
  | `Network message -> `Vault_network_error message

let fetch_secret_map ~sw ~client ~addr ~token ~path =
  let headers = Cohttp.Header.of_list [ ("X-Vault-Token", token) ] in
  let uri = Uri.of_string (secret_endpoint ~addr ~path) in
  let* response =
    get ~sw ~headers:(Some headers) uri client |> Result.map_error (function
      | `Network message -> `Vault_network_error message
      | `Json message -> `Vault_json_error message
      | `Http (code, body) -> `Vault_http_error (code, body))
  in
  if response.status < 200 || response.status >= 300 then
    Error (`Vault_http_error (response.status, response.body))
  else
    let* fields =
      let* json = parse_json response.body |> Result.map_error decode_payload_error in
      decode_payload json
    in
    fields
    |> List.fold_left
         (fun acc (name, value) ->
           let* acc = acc in
           let* value =
             value_to_string value
             |> Result.map_error (fun message -> `Invalid_secret_response message)
           in
           Ok ((name, value) :: acc))
         (Ok [])
    |> Result.map_error decode_payload_error

let source ~sw ~net { addr; token; path } () =
  let* entries =
    fetch_secret_map ~sw ~client:(create ~net) ~addr ~token ~path
  in
  Ok (Some (as_source entries))

let source_from_map entries = as_source entries
