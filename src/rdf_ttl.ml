(*********************************************************************************)
(*                OCaml-RDF                                                      *)
(*                                                                               *)
(*    Copyright (C) 2012-2013 Institut National de Recherche en Informatique     *)
(*    et en Automatique. All rights reserved.                                    *)
(*                                                                               *)
(*    This program is free software; you can redistribute it and/or modify       *)
(*    it under the terms of the GNU Lesser General Public License version        *)
(*    3 as published by the Free Software Foundation.                            *)
(*                                                                               *)
(*    This program is distributed in the hope that it will be useful,            *)
(*    but WITHOUT ANY WARRANTY; without even the implied warranty of             *)
(*    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *)
(*    GNU General Public License for more details.                               *)
(*                                                                               *)
(*    You should have received a copy of the GNU General Public License          *)
(*    along with this program; if not, write to the Free Software                *)
(*    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA                   *)
(*    02111-1307  USA                                                            *)
(*                                                                               *)
(*    Contact: Maxence.Guesdon@inria.fr                                          *)
(*                                                                               *)
(*********************************************************************************)

(** *)

open Rdf_graph ;;
open Rdf_ttl_types;;

type error =
| Parse_error of Rdf_loc.loc * string
| Unknown_namespace of string

exception Error of error

let string_of_error = function
  Parse_error (loc, s) ->
    (Rdf_loc.string_of_loc loc) ^ s
| Unknown_namespace s ->
    "Unknown namespace '" ^ s ^ "'"
;;

let iri_of_iriref ctx s = Rdf_iri.ensure_absolute ctx.base s;;

let iri_of_resource ctx = function
  Iriref iri -> iri_of_iriref ctx iri
| Qname (p, n) ->
    (*prerr_endline
      (Printf.sprintf "Qname(%S, %S)"
       (match p with None -> "" | Some s -> s)
         (match n with None -> "" | Some s -> s)
      );
    *)
    let p = match p with None -> "" | Some s -> s in
    begin
      let base =
        try SMap.find p ctx.prefixes
        with Not_found ->
            raise (Error (Unknown_namespace p))
      in
      match n with
        None -> base
      | Some n ->
          let iri = (Rdf_iri.string base)^n in
          (*prerr_endline (Printf.sprintf "Apply prefix: p=%s, => base=%s, n=%s" p (Rdf_iri.string base) n);*)
          Rdf_iri.iri iri
    end
;;

let rec mk_blank ctx g = function
  NodeId id ->
    let (node, gstate) = Rdf_xml.get_blank_node g ctx.gstate id in
    (node, { ctx with gstate }, g)
| Empty ->
    let node = Rdf_term.Blank_ (g.new_blank_id ()) in
    (node, ctx, g)
| PredObjs l ->
    let node = Rdf_term.Blank_ (g.new_blank_id ()) in
    let (ctx, g) = List.fold_left (insert_sub_predobj node) (ctx, g) l in
    (node, ctx, g)
| Collection [] -> (Rdf_term.Iri Rdf_rdf.rdf_nil, ctx, g)
| Collection objects ->
    let node = Rdf_term.Blank_ (g.new_blank_id ()) in
    let (ctx, g) = mk_collection ctx g node objects in
    (node, ctx, g)

and mk_collection ctx g node = function
  [] -> assert false
| h :: q ->
   let (obj, ctx, g) = mk_object_node ctx g h in
   g.add_triple ~sub: node ~pred: Rdf_rdf.rdf_first ~obj;
   match q with
     [] ->
        g.add_triple ~sub: node
         ~pred: Rdf_rdf.rdf_rest
         ~obj: (Rdf_term.Iri Rdf_rdf.rdf_nil);
       (ctx, g)
   | _ ->
       let obj = Rdf_term.Blank_ (g.new_blank_id ()) in
        g.add_triple ~sub: node
          ~pred: Rdf_rdf.rdf_rest
          ~obj ;
       mk_collection ctx g obj q

and mk_object_node ctx g = function
  | Obj_iri res -> (Rdf_term.Iri (iri_of_resource ctx res), ctx, g)
  | Obj_blank b -> mk_blank ctx g b
  | Obj_literal (String (s, lang, typ)) ->
       let typ =
         match typ with
           None -> None
         | Some r -> Some (iri_of_resource ctx r)
       in
       let lit = Rdf_term.mk_literal ?typ ?lang s in
       (Rdf_term.Literal lit, ctx, g)

and insert_pred sub pred (ctx, g) obj =
  let (obj, ctx, g) = mk_object_node ctx g obj in
  g.add_triple ~sub ~pred ~obj;
  (ctx, g)

and insert_sub_predobj sub (ctx, g) (pred, objs) =
  let pred =
    match pred with
      Pred_iri r -> iri_of_resource ctx r
    | Pred_a -> Rdf_rdf.rdf_type
  in
  List.fold_left (insert_pred sub pred) (ctx, g) objs

and insert_sub_predobjs ctx g sub l =
  let (sub, ctx, g) =
    match sub with
      Sub_iri r -> (Rdf_term.Iri (iri_of_resource ctx r), ctx, g)
    | Sub_blank b -> mk_blank ctx g b
  in
  List.fold_left (insert_sub_predobj sub) (ctx, g) l
;;

let apply_statement (ctx, g) = function
  Directive (Prefix (s, iri)) ->
    (*prerr_endline (Printf.sprintf "Directive (Prefix (%S, %s))" s iri);*)
    let iri = iri_of_iriref ctx iri in
    (*prerr_endline (Printf.sprintf "iri=%s" (Rdf_iri.string iri));*)
    let ctx = { ctx with prefixes = SMap.add s iri ctx.prefixes } in
    (ctx, g)
| Directive (Base iri) ->
    let iri = iri_of_iriref ctx iri in
    let ctx = { ctx with base = iri } in
    (ctx, g)
| Triples (subject, predobjs) ->
    insert_sub_predobjs ctx g subject predobjs
;;

let apply_statements ctx g l =
  List.fold_left apply_statement (ctx, g) l
;;

open Lexing;;


let from_lexbuf g ?(base=g.Rdf_graph.name()) ?fname lexbuf =
  let gstate = {
      Rdf_xml.blanks = SMap.empty ;
      gnamespaces = Rdf_iri.Irimap.empty ;
    }
  in
  let ctx = {
      base = base ;
      prefixes = Rdf_ttl_types.SMap.empty ;
      gstate }
  in
  let parse = Rdf_ulex.menhir_with_ulex Rdf_ttl_parser.main Rdf_ttl_lex.main ?fname in
  let statements =
    try parse lexbuf
    with Rdf_ulex.Parse_error (e, pos)->
        let msg =
          match e with
            Rdf_ttl_parser.Error ->
              let lexeme = Ulexing.utf8_lexeme lexbuf in
              Printf.sprintf "Parse error on lexeme %S" lexeme
          | Failure msg ->
              msg
          | Rdf_iri.Invalid_iri (s, msg) ->
              "Invalid IRI "^s^" : "^msg
          | e -> Printexc.to_string e
        in
        let loc = { Rdf_loc.loc_start = pos ; loc_end = pos } in
        raise (Error (Parse_error (loc,msg)))
  in
  let (ctx, g) = apply_statements ctx g statements in
  (* add namespaces *)
  let add_ns prefix iri = g.add_namespace iri prefix in
  Rdf_ttl_types.SMap.iter add_ns ctx.prefixes
;;

let from_string g ?base s =
  let lexbuf = Ulexing.from_utf8_string s in
  from_lexbuf g ?base lexbuf
;;

let from_file g ?base file =
  let ic = open_in_bin file in
  let lexbuf = Ulexing.from_utf8_channel ic in
  try from_lexbuf g ?base ~fname: file lexbuf
  with e ->
      close_in ic;
      raise e
;;

let escape_reserved_chars =
  let rec iter b len s i =
    if i >= len then
      ()
    else
      begin
        let size = Rdf_utf8.utf8_nb_bytes_of_char s.[i] in
        (match size with
          1 when Rdf_types.CSet.mem s.[i] Rdf_ttl_lex.reserved_chars ->
            Buffer.add_char b '\\' ;
            Buffer.add_char b s.[i]
        | _ ->
            Buffer.add_string b (String.sub s i size)
        );
        iter b len s (i+size)
      end
  in
  fun s ->
    let len = String.length s in
    let b = Buffer.create len in
    iter b len s 0;
    Buffer.contents b
;;

let string_of_triple ~sub ~pred ~obj =
  (Rdf_term.string_of_term sub)^" "^
  (Rdf_term.string_of_term (Rdf_term.Iri pred))^" "^
  (Rdf_term.string_of_term obj)^" ."
;;

let string_of_triple_ns ns ~sub ~pred ~obj =
  let string_of term =
    match term with
    | Rdf_term.Blank | Rdf_term.Blank_ _ -> Rdf_term.string_of_term term
    | Rdf_term.Literal lit ->
        (Rdf_term.quote_str lit.Rdf_term.lit_value) ^
          (match lit.Rdf_term.lit_language with
             None -> ""
           | Some l -> "@" ^ l
          ) ^
          (match lit.Rdf_term.lit_type with
             None -> ""
           | Some iri ->
               let iri = Rdf_iri.string iri in
               let s =
                 match Rdf_dot.apply_namespaces ns iri with
                   ("",iri) -> "<"^iri^">"
                 | (pref,s) -> pref ^ ":" ^ (escape_reserved_chars s)
               in
               "^^" ^ s
          )
    | Rdf_term.Iri iri ->
        let s = Rdf_iri.string iri in
        match Rdf_dot.apply_namespaces ns s with
          ("",iri) -> "<" ^ iri ^ ">"
        | (pref,s) -> pref ^ ":" ^ (escape_reserved_chars s)
  in
  let sub = string_of sub in
  let pred = string_of (Rdf_term.Iri pred) in
  let obj = string_of obj in
  sub ^ " " ^ pred ^ " " ^ obj^ " ."
;;

let f_triple ns print (sub, pred, obj) =
  print (string_of_triple_ns ns ~sub ~pred ~obj)
;;

let string_of_namespace (pref,iri) = "@prefix "^pref^": <"^iri^"> .";;

let to_ ?namespaces print g =
  let ns = Rdf_dot.build_namespaces ?namespaces g in
  List.iter (fun ns -> print (string_of_namespace ns)) ns;
  List.iter (f_triple ns print) (g.find ())

let to_string ?namespaces g =
  let b = Buffer.create 256 in
  let print s = Buffer.add_string b (s^"\n") in
  to_ ?namespaces print g;
  Buffer.contents b
;;


let to_file ?namespaces g file =
  let oc = open_out_bin file in
  try
    let print s = output_string oc (s^"\n") in
    to_ ?namespaces print g;
    close_out oc
  with e ->
      close_out oc;
      raise e
;;


