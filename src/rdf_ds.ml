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

module Irimap = Rdf_uri.Urimap
module Iriset = Rdf_uri.Uriset

exception Could_not_retrieve_graph of Rdf_uri.uri * string
let could_not_retrieve_graph uri msg =
  raise (Could_not_retrieve_graph (uri, msg))
;;

type dataset =
  { default : Rdf_graph.graph ;
    named : Iriset.t ;
    get_named : Rdf_uri.uri -> Rdf_graph.graph ;
  }

let simple_dataset ?(named=[]) default =
  let named_set = List.fold_left (fun set (uri,_) -> Iriset.add uri set) Iriset.empty named in
  let named = List.fold_left (fun map (uri,g) -> Irimap.add uri g map) Irimap.empty named in
  let get_named uri =
    try Irimap.find uri named
    with Not_found ->
        could_not_retrieve_graph uri
          ("Unknown graph "^(Rdf_uri.string uri))
  in
  { default ; named = named_set ; get_named }
;;

let dataset ?get_named ?(named=Iriset.empty) default =
  match get_named with
    None -> simple_dataset default
  | Some get_named -> { default ; named ; get_named }
;;
