(** *)

open Rdf_types;;

let dbg = Rdf_misc.create_log_fun ~prefix: "Rdf_world" "ORDF_WORLD";;

(**/**)
module Raw =
  struct
    external new_world : unit -> world option = "ml_librdf_new_world"
    external free : world -> unit = "ml_librdf_free_world"
    external open_world : world -> unit = "ml_librdf_world_open"
    external set_rasqal : world -> rasqal_world option -> unit = "ml_librdf_world_set_rasqal"
    external get_rasqal : world -> rasqal_world option = "ml_librdf_world_get_rasqal"
    external init_mutex : world -> unit = "ml_librdf_world_init_mutex"
    external set_digest : world -> string -> unit = "ml_librdf_world_set_digest"

    external pointer_of_world : world -> Nativeint.t = "ml_pointer_of_custom"
end
let free v =
  dbg (fun () -> Printf.sprintf "Freeing world %s"
   (Nativeint.to_string (Raw.pointer_of_world v)));
  Raw.free v
;;
let to_finalise v = () (*Gc.finalise free v;;*)
(**/**)

exception World_creation_failed of string;;

let on_new_world fun_name = function
  None -> raise (World_creation_failed fun_name)
| Some n -> to_finalise n; n
;;

let new_world () = on_new_world "" (Raw.new_world ());;
let open_world = Raw.open_world;;
let set_rasqal = Raw.set_rasqal;;
let get_rasqal = Raw.get_rasqal;;
let init_mutex = Raw.init_mutex;;
let set_digest = Raw.set_digest;;