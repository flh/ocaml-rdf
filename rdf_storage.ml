(** *)

open Rdf_types;;

let dbg = Rdf_misc.create_log_fun ~prefix: "Rdf_storage" "ORDF_STORAGE";;

(**/**)
module Raw =
  struct
    external new_storage : world ->
      string -> string -> string -> storage option = "ml_librdf_new_storage"

    external new_with_options : world ->
      string -> string -> hash -> storage option = "ml_librdf_new_storage_with_options"

    external new_from_storage : storage -> storage option =
      "ml_librdf_new_storage_from_storage"

    external free : storage -> unit = "ml_librdf_free_storage"

    external new_from_factory : world ->
      storage_factory -> string -> hash -> storage option =
      "ml_librdf_new_storage_from_factory"

    external open_storage : storage -> model -> bool =
      "ml_librdf_storage_open"
    external close : storage -> bool =
      "ml_librdf_storage_close"

    external size : storage -> int =
      "ml_librdf_storage_size"

    external add_statement : storage -> statement -> int =
      "ml_librdf_storage_add_statement"

    external add_statements : storage -> statement stream -> int =
      "ml_librdf_storage_add_statements"

    external remove_statement : storage -> statement -> int =
      "ml_librdf_storage_remove_statement"

    external contains_statement : storage -> statement -> int =
      "ml_librdf_storage_contains_statement"

    external serialise : storage -> statement stream option =
      "ml_librdf_storage_serialise"

    external find_statements : storage -> statement -> statement stream option =
      "ml_librdf_storage_find_statements"

    external find_statements_with_options :
      storage -> statement -> node option -> hash option -> statement stream option =
      "ml_librdf_storage_find_statements_with_options"

    external get_sources : storage -> node -> node -> node iterator option =
      "ml_librdf_storage_get_sources"
    external get_arcs : storage -> node -> node -> node iterator option =
      "ml_librdf_storage_get_arcs"
    external get_targets : storage -> node -> node -> node iterator option =
      "ml_librdf_storage_get_targets"

    external get_arcs_in : storage -> node -> node iterator option =
      "ml_librdf_storage_get_arcs_in"
    external get_arcs_out : storage -> node -> node iterator option =
      "ml_librdf_storage_get_arcs_out"

    external has_arc_in : storage -> node -> node -> bool =
      "ml_librdf_storage_has_arc_in"
    external has_arc_out : storage -> node -> node -> bool =
      "ml_librdf_storage_has_arc_out"

    external context_add_statement : storage -> node -> statement -> int =
      "ml_librdf_storage_context_add_statement"
    external context_add_statements : storage -> node -> statement stream -> int =
      "ml_librdf_storage_context_add_statements"
    external context_remove_statement : storage -> node -> statement -> int =
      "ml_librdf_storage_context_remove_statement"

    external context_as_stream : storage -> node -> statement stream option =
      "ml_librdf_storage_context_as_stream"

    external supports_query : storage -> query -> bool =
      "ml_librdf_storage_supports_query"

    external query_execute : storage -> query -> query_results option =
      "ml_librdf_storage_query_execute"

    external sync : storage -> int = "ml_librdf_storage_sync"

    external find_statements_in_context :
      storage -> statement -> node option -> statement stream option =
      "ml_librdf_storage_find_statements_in_context"

    external get_contexts : storage -> node iterator option =
      "ml_librdf_storage_get_contexts"

    external get_feature : storage -> uri -> node option =
      "ml_librdf_storage_get_feature"

    external set_feature : storage -> uri -> node -> int =
      "ml_librdf_storage_set_feature"

    external transaction_commit : storage -> int = "ml_librdf_storage_transaction_commit"
    external transaction_get_handle : storage -> 'a = "ml_librdf_storage_transaction_get_handle"
    external transaction_rollback : storage -> int = "ml_librdf_storage_transaction_rollback"
    external transaction_start : storage -> int = "ml_librdf_storage_transaction_start"
    external transaction_start_with_handle :
      storage -> 'a -> int = "ml_librdf_storage_transaction_start_with_handle"

    external get_world : storage -> world = "ml_librdf_storage_get_world"

    external pointer_of_storage : storage -> Nativeint.t = "ml_pointer_of_custom"
   end

let free v =
  dbg (fun () -> Printf.sprintf "Freeing storage %s"
   (Nativeint.to_string (Raw.pointer_of_storage v)));
  Raw.free v
;;
let to_finalise v = Gc.finalise free v;;

(**/**)

exception Storage_creation_failed of string;;
exception Illegal_statement
exception No_such_feature of uri;;

let on_new_storage fun_name = function
  None -> raise (Storage_creation_failed fun_name)
| Some n -> to_finalise n; n
;;

let new_storage ?(options="") world ~factory ~name =
  on_new_storage "" (Raw.new_storage world factory name options)
;;

let new_with_options world ~factory ~name hash =
 on_new_storage "with_options" (Raw.new_with_options world factory name hash)
;;

let copy_storage storage =
  on_new_storage "from_storage" (Raw.new_from_storage storage)
;;

let new_from_factory world factory ~name hash =
 on_new_storage "from_factory" (Raw.new_from_factory world factory name hash)
;;

let open_storage storage model =
  if not (Raw.open_storage storage model) then
    failwith "storage_open"
;;

let close storage =
  if not (Raw.close storage) then
    failwith "storage_close"
;;

let size storage =
  let n = Raw.size storage in
  if n < 0 then None else Some n
;;

let add_statement storage ?context statement =
  let n =
    match context with
      None -> Raw.add_statement storage statement
    | Some node -> Raw.context_add_statement storage node statement
  in
  if n < 0 then failwith "storage_add_statement";
  if n > 0 then raise Illegal_statement
;;

let add_statements storage ?context stream =
  let n =
    match context with
      None -> Raw.add_statements storage stream
    | Some node -> Raw.context_add_statements storage node stream
  in
  if n <> 0 then
   failwith "storage_add_statements"
;;

let remove_statement storage ?context statement =
  let n =
    match context with
     None -> Raw.remove_statement storage statement
   | Some node -> Raw.context_remove_statement storage node statement
  in
  if n <> 0 then
   failwith "storage_remove_statement"
;;

let contains_statement storage statement =
  let n = Raw.contains_statement storage statement in
  if n > 0 then raise Illegal_statement;
  (n = 0)
;;

let serialise ?context storage =
  let s =
    match context with
      None -> Raw.serialise storage
    | Some node -> Raw.context_as_stream storage node
  in
  Rdf_stream.on_new_stream "storage_serialise" s
;;

let find_statements storage ?context ?hash statement =
  match context, hash with
    Some _, None ->
      Rdf_stream.on_new_stream "storage_find_statements_in_context"
        (Raw.find_statements_in_context storage statement context)
  | None, None ->
      Rdf_stream.on_new_stream "storage_find_statements"
      (Raw.find_statements storage statement)
  | _ ->
      Rdf_stream.on_new_stream "storage_find_statements_with_options"
         (Raw.find_statements_with_options
            storage statement context hash)
;;

let get_sources storage ~arc ~target =
  Rdf_iterator.on_new_iterator "storage_get_sources"
    (Raw.get_sources storage arc target)
;;

let get_arcs storage ~source ~target =
  Rdf_iterator.on_new_iterator "storage_get_arcs"
    (Raw.get_arcs storage source target)
;;

let get_targets storage ~source ~arc =
  Rdf_iterator.on_new_iterator "storage_get_targets"
    (Raw.get_targets storage source arc)
;;

let get_arcs_in storage node =
  Rdf_iterator.on_new_iterator "storage_get_arcs_in"
    (Raw.get_arcs_in storage node)
;;

let get_arcs_out storage node =
  Rdf_iterator.on_new_iterator "storage_get_arcs_out"
    (Raw.get_arcs_out storage node)
;;

let has_arc_in storage ~node ~property =
  Raw.has_arc_in storage node property;;

let has_arc_out storage ~node ~property =
  Raw.has_arc_in storage node property;;

let supports_query = Raw.supports_query;;

let query_execute storage query =
  Rdf_query_results.on_new_query_results "storage_query_execute"
    (Raw.query_execute storage query)
;;

let sync storage =
  if Raw.sync storage <> 0 then failwith "storage_sync"
;;

let get_contexts storage =
  Rdf_iterator.on_new_iterator "storage_get_contexts"
    (Raw.get_contexts storage)
;;

let get_feature storage uri =
  match Raw.get_feature storage uri with
    None -> None
  | n -> Some (Rdf_node.on_new_node "" n)
;;

let set_feature storage uri value =
  let n = Raw.set_feature storage uri value in
  if n < 0 then raise (No_such_feature uri);
  if n > 0 then failwith "storage_set_feature"
;;

let transaction_commit storage =
  let n = Raw.transaction_commit storage in
  if n <> 0 then failwith "storage_transaction_commit"
;;

let transaction_get_handle storage =
  Raw.transaction_get_handle storage
;;

let transaction_rollback storage =
  let n = Raw.transaction_rollback storage in
  if n <> 0 then failwith "storage_transaction_rollback"
;;

let transaction_start storage =
  let n = Raw.transaction_start storage in
  if n <> 0 then failwith "storage_transaction_start"
;;

let transaction_start_with_handle storage h =
  let n = Raw.transaction_start_with_handle storage h in
  if n <> 0 then failwith "storage_transaction_start_with_handle"
;;

let get_world storage =
  Rdf_init.on_new_world "storage_get_world" (Some (Raw.get_world storage))
;;