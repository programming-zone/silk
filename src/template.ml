
(*
 * Template instantiation.
 *)

open Parsetree

module TemplateM = Map.Make(String)

let ( let* ) x f = Result.bind x f
let ( let+ ) x f = Result.map f x

let rec serialize_type t = match t with
  | I8  -> "i8"
  | I16 -> "i16"
  | I32 -> "i32"
  | I64 -> "i64"
  | U8  -> "u8"
  | U16 -> "u16"
  | U32 -> "u32"
  | U64 -> "u64"
  | F32 -> "f32"
  | F64 -> "f64"
  | Void -> "void"
  | Bool -> "bool"
  | TypeAlias name -> name
  | Template name -> name
  | Function (ats, rt) ->
     "func(" ^
       (String.concat "," @@ List.map serialize_type ats)
       ^ ")" ^ (serialize_type rt)
  | Pointer t -> "*" ^ (serialize_type t)
  | MutPointer t -> "mut*" ^ (serialize_type t)
  | Array (i, t) -> "[" ^ (string_of_int i) ^ "]" ^ (serialize_type t)
  | Struct (packed, ts) ->
     let prefix = if packed then "(:" else "(" in
     let suffix = if packed then ":)" else ")" in
     prefix ^ (String.concat "," @@ List.map serialize_type ts) ^ suffix
  | StructLabeled (packed, pairs) ->
     let prefix = if packed then "(:" else "(" in
     let suffix = if packed then ":)" else ")" in
     let serialize_pair (n, t) = n ^ "|" ^ (serialize_type t) in
     prefix ^ (String.concat "," @@ List.map serialize_pair pairs) ^ suffix
  | AliasTemplateInstance (name, ts) ->
     name ^ "<" ^ (String.concat "," @@ List.map serialize_type ts) ^ ">"
  | TypeOf expr -> "" (* TODO this is a big yikes *)

let rec map_stmt tmap s =
  let map_vd tmap vd = match vd with
    | ValI (n, e) -> let+ e = map_expr tmap e in ValI (n, e)
    | VarI (n, e) -> let+ e = map_expr tmap e in ValI (n, e)
    | Val (n, t, e) ->
       let* t = map_type tmap t in
       let+ e = map_expr tmap e in
       Val (n, t, e)
    | Var (n, t, e) ->
       let* t = map_type tmap t in
       let+ e = map_expr tmap e in
       Var (n, t, e)
  in
  match s with
  | Empty | Continue | Break | Return None -> Ok s
  | Decl vd -> let+ vd = map_vd tmap vd in Decl vd
  | Expr e -> let+ e = map_expr tmap e in Expr e
  | Block ss ->
     let+ ss = Util.map_join (map_stmt tmap) ss in
     Block ss
  | IfElse (e, s1, s2) ->
     let* e = map_expr tmap e in
     let* s1 = map_stmt tmap s1 in
     let+ s2 = map_stmt tmap s2 in
     IfElse (e, s1, s2)
  | While (e, s) ->
     let* e = map_expr tmap e in
     let+ s = map_stmt tmap s in
     While (e, s)
  | For (vd, e1, e2, s) ->
     let* vd = map_vd tmap vd in
     let* e1 = map_expr tmap e1 in
     let* e2 = map_expr tmap e2 in
     let+ s = map_stmt tmap s in
     For (vd, e1, e2, s)
  | Return (Some e) ->
     let+ e = map_expr tmap e in
     Return (Some e)

and map_expr tmap e = match e with
  | Identifier _ | Literal _ -> Ok e
  | Assignment (l, r) ->
     let* l = map_expr tmap l in
     let+ r = map_expr tmap r in
     Assignment (l, r)
  | TemplateInstance (name, ts) ->
     let+ ts = Util.map_join (map_type tmap) ts in
     TemplateInstance (name, ts)
  | StructLiteral (packed, es) ->
     let+ es = Util.map_join (map_expr tmap) es in
     StructLiteral (packed, es)
  | StructInit (t, es) ->
     let* t = map_type tmap t in
     let+ es = Util.map_join (map_expr tmap) es in
     StructInit (t, es)
  | ArrayElems es -> let+ es = Util.map_join (map_expr tmap) es in ArrayElems (es)
  | ArrayInit (t, i) -> let+ t = map_type tmap t in ArrayInit (t, i)
  | FunctionCall (fe, fes) ->
     let* fe = map_expr tmap fe in
     let+ fes = Util.map_join (map_expr tmap) fes in
     FunctionCall (fe, fes)
  | TypeCast (t, e) ->
     let* t = map_type tmap t in
     let+ e = map_expr tmap e in
     TypeCast (t, e)
  | BinOp (l, o, r) ->
     let* l = map_expr tmap l in
     let+ r = map_expr tmap r in
     BinOp (l, o, r)
  | UnOp (o, e) -> let+ e = map_expr tmap e in UnOp (o, e)
  | Index (a, b) ->
     let* a = map_expr tmap a in
     let+ b = map_expr tmap b in
     Index (a, b)
  | StructMemberAccess (e, s) ->
     let+ e = map_expr tmap e in StructMemberAccess (e, s)
  | StructIndexAccess (e, i) ->
     let+ e = map_expr tmap e in StructIndexAccess (e, i)

and map_type tmap t =
  match t with
  | Template name ->
     begin match TemplateM.find_opt name tmap with
     | Some t -> Ok t
     | None -> Error ("Error: Undefined template " ^ name)
     end
  | Function (ts, rt) ->
     let* rt = map_type tmap rt in
     let+ args = Util.map_join (map_type tmap) ts in
     Function (args, rt)
  | Pointer t -> let+ t = map_type tmap t in Pointer t
  | MutPointer t -> let+ t = map_type tmap t in MutPointer t
  | Array (i, t) -> let+ t = map_type tmap t in Array (i, t)
  | StructLabeled (packed, pairs) ->
     let (names, types) = List.split pairs in
     let+ mts = Util.map_join (map_type tmap) types in
     let pairs = List.combine names mts in
     StructLabeled (packed, pairs)
  | Struct (packed, ts) ->
     let+ mts = Util.map_join (map_type tmap) ts in
     Struct (packed, mts)
  | AliasTemplateInstance (name, ts) ->
     let+ ts = Util.map_join (map_type tmap) ts in
     AliasTemplateInstance (name, ts)
  | TypeOf e -> let+ e = map_expr tmap e in TypeOf e
  | I8 | I16 | I32 | I64 | U8 | U16 | U32 | U64 | F32 | F64
    | Void | Bool | TypeAlias _ -> Ok t

let add_object f decls os o =
  let (decls, o) = f decls o in
  decls, o :: os

let rec trav_type decls t = match t with
  | I8 | I16 | I32 | I64
    | U8 | U16 | U32 | U64
    | F32 | F64 | Void | Bool | TypeAlias _ | Template _ -> decls, t
  | Function (ts, rt) ->
     let (decls, ts) = Util.f2l (add_object trav_type) decls [] ts in
     let (decls, rt) = trav_type decls rt in
     decls, Function (List.rev ts, rt)
  | Pointer t ->
     let (decls, t) = trav_type decls t in
     decls, Pointer t
  | MutPointer t ->
     let (decls, t) = trav_type decls t in
     decls, MutPointer t
  | Array (i, t) ->
     let (decls, t) = trav_type decls t in
     decls, Array (i, t)
  | StructLabeled (packed, members) ->
     let (names, ts) = List.split members in
     let (decls, ts) = Util.f2l (add_object trav_type) decls [] ts in
     let members = List.combine names @@ List.rev ts in
     decls, StructLabeled (packed, members)
  | Struct (packed, ts) ->
     let (decls, ts) = Util.f2l (add_object trav_type) decls [] ts in
     decls, Struct (packed, List.rev ts)
  | TypeOf e ->
     let (decls, e) = trav_expr decls e in
     decls, TypeOf e

  | AliasTemplateInstance (name, types) ->
     (* TODO *)
     let rec create_td l = match Util.assoc name l with
       | Some (TemplateTypeDef (templates, (name, type_)), _) ->
          let add_template tmap (name, type_) = TemplateM.add name type_ tmap
          in
          let tmap =
            List.fold_left add_template TemplateM.empty @@
              List.combine templates types
          in
          let t = map_type tmap type_ in
          (* TODO move everything into result monad? *)
          begin match t with
          | Ok t ->
             let n = serialize_type @@ AliasTemplateInstance (name, types) in
             (((n, TypeDef (n, t)) :: decls), AliasTemplateInstance (name, types))
          | Error _ -> decls, AliasTemplateInstance (name, types)
          end
       | Some (TemplateTypeFwdDef _, l) -> create_td l
       | _ -> decls, t
     in
     create_td decls

and trav_expr decls e = match e with
  | Identifier _ | Literal _ -> decls, e
  | Assignment (l, r) ->
     let (decls, r) = trav_expr decls r in
     let (decls, l) = trav_expr decls l in
     decls, Assignment (l, r)
  | StructLiteral (packed, es) ->
     let (decls, es) = Util.f2l (add_object trav_expr) decls [] es in
     decls, StructLiteral (packed, List.rev es)
  | StructInit (t, es) ->
     let (decls, t) = trav_type decls t in
     let (decls, es) = Util.f2l (add_object trav_expr) decls [] es in
     decls, StructInit (t, List.rev es)
  | ArrayElems es ->
     let (decls, es) = Util.f2l (add_object trav_expr) decls [] es in
     decls, ArrayElems (List.rev es)
  | ArrayInit (t, i) ->
     let (decls, t) = trav_type decls t in
     decls, ArrayInit (t, i)
  | FunctionCall (e, es) ->
     let (decls, e) = trav_expr decls e in
     let (decls, es) = Util.f2l (add_object trav_expr) decls [] es in
     decls, FunctionCall (e, List.rev es)
  | TypeCast (t, e) ->
     let (decls, t) = trav_type decls t in
     let (decls, e) = trav_expr decls e in
     decls, TypeCast (t, e)
  | BinOp (l, o, r) ->
     let (decls, l) = trav_expr decls l in
     let (decls, r) = trav_expr decls r in
     decls, BinOp (l, o, r)
  | UnOp (o, e) ->
     let (decls, e) = trav_expr decls e in
     decls, UnOp (o, e)
  | Index (a, b) ->
     let (decls, a) = trav_expr decls a in
     let (decls, b) = trav_expr decls b in
     decls, Index (a, b)
  | StructMemberAccess (e, s) ->
     let (decls, e) = trav_expr decls e in
     decls, StructMemberAccess (e, s)
  | StructIndexAccess (e, i) ->
     let (decls, e) = trav_expr decls e in
     decls, StructIndexAccess (e, i)

  | TemplateInstance (name, types) ->
     (* TODO *)
     decls, e

let trav_vd decls vd =
  let (name, expr) = match vd with
    | Val (name, _, expr) -> (name, expr)
    | ValI (name, expr) -> (name, expr)
    | Var (name, _, expr) -> (name, expr)
    | VarI (name, expr) -> (name, expr)
  in
  let (decls, expr) = trav_expr decls expr in
  decls,
  match vd with
  | Val (name, t, _) -> Val (name, t, expr)
  | ValI (name, _) -> ValI (name, expr)
  | Var (name, t, _) -> Var (name, t, expr)
  | VarI (name, _) -> VarI (name, expr)


let rec trav_stmt decls s = match s with
  | Empty | Continue | Break | Return None -> decls, s
  | Decl vd ->
     let (decls, vd) = trav_vd decls vd in
     decls, Decl vd
  | Expr e ->
     let (decls, e) = trav_expr decls e in
     decls, Expr e
  | Block ss ->
     let (decls, ss) = Util.f2l (add_object trav_stmt) decls [] ss in
     decls, Block (List.rev ss)
  | IfElse (e, s1, s2) ->
     let (decls, e) = trav_expr decls e in
     let (decls, s1) = trav_stmt decls s1 in
     let (decls, s2) = trav_stmt decls s2 in
     decls, IfElse (e, s1, s2)
  | While (e, s) ->
     let (decls, e) = trav_expr decls e in
     let (decls, s) = trav_stmt decls s in
     decls, While (e, s)
  | For (vd, e1, e2, s) ->
     let (decls, vd) = trav_vd decls vd in
     let (decls, e1) = trav_expr decls e1 in
     let (decls, e2) = trav_expr decls e2 in
     let (decls, s) = trav_stmt decls s in
     decls, For (vd, e1, e2, s)
  | Return (Some e) ->
     let (decls, e) = trav_expr decls e in
     decls, Return (Some e)

let trav_top_decl decls decl = match decl with
  | TypeDef (name, t) ->
     let (decls, t) = trav_type decls t in
     (name, TypeDef (name, t)) :: decls
  | TypeFwdDef name -> (name, decl) :: decls

  | ValDecl (pub, vd) ->
     let (name, expr) = match vd with
       | Val (name, _, expr) -> (name, expr)
       | ValI (name, expr) -> (name, expr)
       | Var (name, _, expr) -> (name, expr)
       | VarI (name, expr) -> (name, expr)
     in
     let (decls, vd) = trav_vd decls vd in
     (name, ValDecl (pub, vd)) :: decls

  | FuncDecl (pub, fd) ->
     let (name, args, rettype, body) = fd in
     let (decls, rettype) = trav_type decls rettype in
     let add_arg decls args arg =
       let (name, t) = arg in
       let (decls, t) = trav_type decls t in
       (decls, (name, t) :: args)
     in
     let (decls, args) = Util.f2l add_arg decls [] args in
     let args = List.rev args in
     let (decls, body) = trav_stmt decls body in
     (name, FuncDecl (pub, (name, args, rettype, body))) :: decls

  | TemplateTypeDef (_, (name, _)) -> (name, decl) :: decls
  | TemplateTypeFwdDef (_, name) -> (name, decl) :: decls

  (* TODO *)
  | _ -> decls

let process_file f =
  let (_, f) =
    List.split @@ List.rev @@ List.fold_left trav_top_decl [] f
  in f
