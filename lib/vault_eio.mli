type error =
  [ `Missing_vault_configuration of string
  | `Vault_http_error of int * string
  | `Vault_json_error of string
  | `Vault_network_error of string
  | `Invalid_secret_response of string ]

module Error : sig
  type t = error
end

type source = string -> string option

type config = {
  addr : string;
  token : string;
  path : string;
}

val error_to_string : error -> string

val source_from_map : (string * string) list -> source

val source :
  sw:Eio.Switch.t ->
  net:[> _ Eio.Net.ty] Eio.Net.t ->
  config ->
  unit ->
  (source option, error) result
